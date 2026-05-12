import 'dart:async';
import 'dart:developer' as dev;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_card.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/scan_history_service.dart';
import '../../../core/services/scan_session_service.dart';
import '../models/scan_session.dart';
import 'scan_session_screen.dart';
import 'all_sessions_screen.dart';
import 'session_setup_screen.dart';
import '../widgets/template_picker_sheet.dart';
import '../../../core/utils/app_router.dart';
import '../widgets/scanner_overlay_widget.dart';

enum ScanScreenMode { standalone, pickForClone }

enum _ScanEntryState { chooser, quickScan, scanToSheet }

enum _ScanAction {
  openUrl,
  copyText,
  copyWifiPassword,
  connectWifi,
  callPhone,
  sendEmail,
  openMap,
  shareText,
  useForClone,
  rescan,
}

class ScanScreen extends StatefulWidget {
  final ScanScreenMode mode;
  final bool isActive;

  const ScanScreen({
    super.key,
    this.mode = ScanScreenMode.standalone,
    this.isActive = true,
  });

  const ScanScreen.pickForClone({super.key})
      : mode = ScanScreenMode.pickForClone,
        isActive = true;

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final _imagePicker = ImagePicker();
  final MobileScannerController _controller = MobileScannerController(
    autoStart: false,
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
    formats: [BarcodeFormat.all],
  );

  bool _isHandlingDetection = false;
  bool _scannerRunning = false;
  bool _isPickingImage = false;
  bool _isBatchMode = false;
  int _batchCount = 0;
  late _ScanEntryState _entryState;

  static const _kSheetGreen = Color(0xFF16A34A);

  bool get _isPickMode => widget.mode == ScanScreenMode.pickForClone;
  bool get _isCameraSurfaceActive =>
      (_isPickMode || widget.isActive) &&
      _entryState == _ScanEntryState.quickScan;

  @override
  void initState() {
    super.initState();
    _entryState =
        _isPickMode ? _ScanEntryState.quickScan : _ScanEntryState.chooser;
    if (_isCameraSurfaceActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _startScanner());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ScanScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive == widget.isActive) return;
    if (_isCameraSurfaceActive) {
      _startScanner();
    } else {
      _stopScanner();
    }
  }

  bool _isCameraActionPending = false;

  Future<void> _updateCameraState() async {
    if (_isCameraActionPending) return;
    _isCameraActionPending = true;

    try {
      if (_isCameraSurfaceActive && !_scannerRunning) {
        await _controller.start();
        if (mounted) setState(() => _scannerRunning = true);
      } else if (!_isCameraSurfaceActive && _scannerRunning) {
        await _controller.stop();
        if (mounted) setState(() => _scannerRunning = false);
      }
    } catch (_) {}

    _isCameraActionPending = false;

    if (mounted) {
      if ((_isCameraSurfaceActive && !_scannerRunning) ||
          (!_isCameraSurfaceActive && _scannerRunning)) {
        _updateCameraState();
      }
    }
  }

  void _startScanner() {
    if (_isCameraSurfaceActive && !_scannerRunning) _updateCameraState();
  }

  void _stopScanner() {
    if (!_isCameraSurfaceActive && _scannerRunning) _updateCameraState();
  }

  void _setEntryState(_ScanEntryState state) {
    setState(() => _entryState = state);
    _updateCameraState();
  }


  Future<void> _scanFromGallery() async {
    if (_isPickingImage) return;
    setState(() => _isPickingImage = true);
    _isHandlingDetection = true;
    dev.log('[GalleryScan] ── started ──', name: 'ScanScreen');

    try {
      final XFile? picked = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 100,
        maxWidth: 2048,
      );

      if (picked == null) {
        dev.log('[GalleryScan] user cancelled', name: 'ScanScreen');
        _isHandlingDetection = false;
        return;
      }

      dev.log(
        '[GalleryScan] picked: ${picked.path}  size=${File(picked.path).statSync().size}',
        name: 'ScanScreen',
      );

      if (_scannerRunning) {
        await _controller.stop();
        if (mounted) setState(() => _scannerRunning = false);
        dev.log('[GalleryScan] camera stopped', name: 'ScanScreen');
      }

      dev.log('[GalleryScan] calling analyzeImage...', name: 'ScanScreen');
      final BarcodeCapture? capture =
          await _controller.analyzeImage(picked.path);

      dev.log(
        '[GalleryScan] capture=$capture  count=${capture?.barcodes.length ?? 0}',
        name: 'ScanScreen',
      );
      if (capture != null) {
        for (int i = 0; i < capture.barcodes.length; i++) {
          dev.log(
            '[GalleryScan] [$i] format=${capture.barcodes[i].format}  raw=${capture.barcodes[i].rawValue}',
            name: 'ScanScreen',
          );
        }
      }

      if (!mounted) return;

      final raw =
          capture?.barcodes
              .map((b) => (b.rawValue ?? '').trim())
              .firstWhere((v) => v.isNotEmpty, orElse: () => '') ??
          '';

      if (raw.isEmpty) {
        dev.log('[GalleryScan] ✗ no barcode found', name: 'ScanScreen');
        _snack('No QR / barcode found in the selected image.', isError: true);
        _isHandlingDetection = false;
        await _resumeCamera();
        return;
      }

      dev.log('[GalleryScan] ✓ raw="$raw"', name: 'ScanScreen');
      _isHandlingDetection = false;
      await _handleScannedValue(raw, resumeAfter: true);
    } catch (e, st) {
      dev.log(
        '[GalleryScan] ✗ EXCEPTION: $e',
        name: 'ScanScreen',
        error: e,
        stackTrace: st,
      );
      if (mounted) _snack('Error reading image: $e', isError: true);
      _isHandlingDetection = false;
      await _resumeCamera();
    } finally {
      if (mounted) setState(() => _isPickingImage = false);
      dev.log('[GalleryScan] ── finished ──', name: 'ScanScreen');
    }
  }

  Future<void> _resumeCamera() async {
    if (!mounted || !_isCameraSurfaceActive) return;
    try {
      await _controller.start();
      if (mounted) setState(() => _scannerRunning = true);
    } catch (_) {}
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_isHandlingDetection) return;
    final raw = capture.barcodes
        .map((b) => b.rawValue?.trim() ?? '')
        .firstWhere((v) => v.isNotEmpty, orElse: () => '');
    if (raw.isEmpty) return;
    await _handleScannedValue(raw, resumeAfter: true);
  }

  Future<void> _handleScannedValue(
    String raw, {
    required bool resumeAfter,
  }) async {
    if (_isHandlingDetection) return;
    _isHandlingDetection = true;
    var shouldResume = resumeAfter;

    try {
      await _controller.stop();
      if (mounted) setState(() => _scannerRunning = false);

      await ScanHistoryService.save(
        ScanEntry(
          raw: raw,
          type: ScanEntry.detectType(raw),
          scannedAt: DateTime.now(),
        ),
      );

      if (_isBatchMode) {
        if (mounted) {
          setState(() => _batchCount++);
          HapticFeedback.heavyImpact();
          await Future.delayed(const Duration(milliseconds: 600));
        }
      } else {
        final action = await _showResultSheet(raw);
        if (!mounted) return;

        if (_isPickMode && action == _ScanAction.useForClone) {
          shouldResume = false;
          Navigator.pop(context, raw);
          return;
        }

      switch (action) {
        case _ScanAction.openUrl:
          final uri = Uri.tryParse(raw);
          if (uri == null) {
            _snack('Invalid URL', isError: true);
          } else {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
          break;
        case _ScanAction.copyText:
          await Clipboard.setData(ClipboardData(text: raw));
          _snack('Copied to clipboard.');
          break;
        case _ScanAction.copyWifiPassword:
          final password = _extractWifiPassword(raw);
          if (password == null || password.isEmpty) {
            _snack('No Wi-Fi password found.', isError: true);
          } else {
            await Clipboard.setData(ClipboardData(text: password));
            _snack('Wi-Fi password copied.');
          }
          break;
        case _ScanAction.connectWifi:
          _snack('Open Settings → Wi-Fi to connect manually.',
              isError: false);
          break;
        case _ScanAction.callPhone:
          final phone =
              raw.startsWith('tel:') ? raw : 'tel:${raw.trim()}';
          final uri = Uri.tryParse(phone);
          if (uri != null) await launchUrl(uri);
          break;
        case _ScanAction.sendEmail:
          final email =
              raw.startsWith('mailto:') ? raw : 'mailto:$raw';
          final uri = Uri.tryParse(email);
          if (uri != null) await launchUrl(uri);
          break;
        case _ScanAction.openMap:
          final uri = Uri.tryParse(raw);
          if (uri != null) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
          break;
        case _ScanAction.shareText:
          await SharePlus.instance.share(ShareParams(text: raw));
          break;
        case _ScanAction.useForClone:
          break;
          case _ScanAction.rescan:
            break;
        }
      }
    } finally {
      if (mounted && shouldResume && _isCameraSurfaceActive) {
        await _controller.start();
        if (mounted) setState(() => _scannerRunning = true);
      }
      _isHandlingDetection = false;
    }
  }

  Future<_ScanAction> _showResultSheet(String raw) async {
    final type = ScanEntry.detectType(raw);
    final result = await showModalBottomSheet<_ScanAction>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) =>
          _ScanResultSheet(raw: raw, type: type, isPickMode: _isPickMode),
    );
    return result ?? _ScanAction.rescan;
  }

  String? _extractWifiPassword(String value) {
    if (!value.startsWith('WIFI:')) return null;
    final match = RegExp(r';P:(.*?);').firstMatch(value);
    return match?.group(1);
  }

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor:
            isError ? context.themeError : context.themeAccent,
      ),
    );
  }

  Future<void> _openNewSession() async {
    _stopScanner();
    final result = await TemplatePicker.show(context);
    if (result.dismissed || !mounted) return;
    await Navigator.push(
      context,
      FadeSlideRoute(
        page: SessionSetupScreen(
          initialTemplate: result.template,
          onSessionEnded: () {
            if (mounted) setState(() {});
          },
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  void _openExistingSession(ScanSession session) {
    _stopScanner();
    Navigator.push(
      context,
      FadeSlideRoute(page: ScanSessionScreen(session: session)),
    ).then((_) {
      if (mounted) setState(() {});
    });
  }

  List<Widget> _buildSessionCard(ScanSession? activeSession) {
    if (activeSession != null) {
      final rowCount = ScanSessionService.getRowCount(activeSession.id);
      return [
        const SizedBox(height: 10),
        GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            _openExistingSession(activeSession);
          },
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF15803D), Color(0xFF16A34A)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: _kSheetGreen.withValues(alpha: 0.35),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.table_chart_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: const BoxDecoration(
                              color: Color(0xFF4ADE80),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            'SHEET ACTIVE',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${activeSession.name} \u00b7 $rowCount ${rowCount == 1 ? 'row' : 'rows'}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'Resume',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ];
    }

    return [
      const SizedBox(height: 10),
      GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          _openNewSession();
        },
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            color: context.themeCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _kSheetGreen.withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: _kSheetGreen.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.table_chart_rounded,
                  color: _kSheetGreen,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'New Sheet',
                      style: TextStyle(
                        color: context.themeTextPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'Scan barcodes into a spreadsheet',
                      style: TextStyle(
                        color: context.themeTextSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: context.themeTextSecondary,
              ),
            ],
          ),
        ),
      ),
    ];
  }

  // ── Chooser UI ────────────────────────────────────────────────────────────
  Widget _buildChooser(ScanSession? activeSession) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 24),
            Text(
              'Scan',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: context.themeTextPrimary,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 24),
            // Quick scan card
            GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                _setEntryState(_ScanEntryState.quickScan);
              },
              child: AppCard(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: context.themeAccent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Icon(
                        Icons.qr_code_scanner_rounded,
                        color: context.themeAccent,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Quick Scan',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: context.themeTextPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Scan once, get instant result',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: context.themeTextSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 14,
                      color: context.themeTextSecondary,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            // Session card (active or new)
            ..._buildSessionCard(activeSession),
            const Spacer(),
            // Past sessions link
            Center(
              child: TextButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    FadeSlideRoute(page: const AllSessionsScreen()),
                  ).then((_) {
                    if (mounted) setState(() {});
                  });
                },
                child: Text(
                  'View past sheets',
                  style: TextStyle(
                    fontSize: 13,
                    color: context.themeTextSecondary,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  // ── Quick scan camera UI ──────────────────────────────────────────────────
  Widget _buildQuickScanCamera() {
    return Stack(
      children: [
        // Full-screen camera
        MobileScanner(
          controller: _controller,
          onDetect: _onDetect,
        ),
        // Overlay
        ScannerOverlayWidget(
          detectionState: _isHandlingDetection
              ? ScannerDetectionState.detected
              : ScannerDetectionState.idle,
        ),
        // Top bar
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                IconButton(
                  onPressed: () {
                    if (_isPickMode) {
                      Navigator.pop(context);
                    } else {
                      _setEntryState(_ScanEntryState.chooser);
                    }
                  },
                  icon: const Icon(Icons.close_rounded),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black45,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
        // Bottom controls
        Positioned(
          left: 0,
          right: 0,
          bottom: 40,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_isBatchMode && _batchCount > 0)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: context.themeAccent,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$_batchCount scanned',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              // Single / Batch toggle
              Container(
                decoration: BoxDecoration(
                  color: Colors.black45,
                  borderRadius: BorderRadius.circular(30),
                ),
                padding: const EdgeInsets.all(4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() {
                          _isBatchMode = false;
                          _batchCount = 0;
                        });
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                        decoration: BoxDecoration(
                          color: !_isBatchMode ? context.themeAccent : Colors.transparent,
                          borderRadius: BorderRadius.circular(26),
                        ),
                        child: Text(
                          'Single',
                          style: TextStyle(
                            color: !_isBatchMode ? Colors.white : Colors.white70,
                            fontWeight: !_isBatchMode ? FontWeight.bold : FontWeight.w500,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _isBatchMode = true);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                        decoration: BoxDecoration(
                          color: _isBatchMode ? context.themeAccent : Colors.transparent,
                          borderRadius: BorderRadius.circular(26),
                        ),
                        child: Text(
                          'Batch',
                          style: TextStyle(
                            color: _isBatchMode ? Colors.white : Colors.white70,
                            fontWeight: _isBatchMode ? FontWeight.bold : FontWeight.w500,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              // Action buttons row
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Gallery
                  IconButton(
                    onPressed: _isPickingImage ? null : _scanFromGallery,
                    icon: _isPickingImage
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.photo_library_rounded),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black45,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.all(14),
                    ),
                  ),
                  const SizedBox(width: 24),
                  // Torch
                  ValueListenableBuilder(
                    valueListenable: _controller,
                    builder: (_, state, _) {
                      final torchOn = state.torchState == TorchState.on;
                      return IconButton(
                        onPressed: _controller.toggleTorch,
                        icon: Icon(
                          torchOn
                              ? Icons.flash_on_rounded
                              : Icons.flash_off_rounded,
                        ),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black45,
                          foregroundColor: torchOn ? Colors.amber : Colors.white,
                          padding: const EdgeInsets.all(14),
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 24),
                  // Flip
                  IconButton(
                    onPressed: () => _controller.switchCamera(),
                    icon: const Icon(Icons.flip_camera_ios_rounded),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black45,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.all(14),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeSession = ScanSessionService.getActiveSession();

    // In pick-for-clone mode, go straight to camera
    if (_isPickMode) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: _buildQuickScanCamera(),
      );
    }

    switch (_entryState) {
      case _ScanEntryState.chooser:
        return Scaffold(
          backgroundColor: context.themeBg,
          body: _buildChooser(activeSession),
        );
      case _ScanEntryState.quickScan:
        return Scaffold(
          backgroundColor: Colors.black,
          body: _buildQuickScanCamera(),
        );
      case _ScanEntryState.scanToSheet:
        // Phase 3 will replace this with the live scanning overlay
        return Scaffold(
          backgroundColor: context.themeBg,
          appBar: AppBar(title: const Text('Scan to Sheet')),
          body: const Center(child: CircularProgressIndicator()),
        );
    }
  }
}

// ── Result bottom sheet ───────────────────────────────────────────────────────

class _ScanResultSheet extends StatelessWidget {
  final String raw;
  final String type;
  final bool isPickMode;

  const _ScanResultSheet({
    required this.raw,
    required this.type,
    required this.isPickMode,
  });

  bool get _isUrl =>
      raw.startsWith('http://') || raw.startsWith('https://');
  bool get _isWifi => raw.startsWith('WIFI:');
  bool get _isPhone => raw.startsWith('tel:') ||
      RegExp(r'^\+?[0-9\s\-().]{7,}$').hasMatch(raw);
  bool get _isEmail =>
      raw.startsWith('mailto:') || raw.contains('@');
  bool get _isGeoOrMap =>
      raw.startsWith('geo:') || raw.startsWith('https://maps.');

  IconData _typeIcon() {
    if (_isUrl) return Icons.open_in_browser_rounded;
    if (_isWifi) return Icons.wifi_rounded;
    if (_isPhone) return Icons.phone_rounded;
    if (_isEmail) return Icons.email_rounded;
    if (_isGeoOrMap) return Icons.map_rounded;
    return Icons.qr_code_rounded;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          const SizedBox(height: 12),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          // Type icon + value
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: context.themeAccent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(_typeIcon(), color: context.themeAccent, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        type,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: context.themeTextSecondary,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        raw,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: context.themeTextPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 8),
          // Actions
          if (isPickMode) ...[
            _ActionTile(
              icon: Icons.content_copy_rounded,
              label: 'Use this barcode',
              onTap: () => Navigator.pop(context, _ScanAction.useForClone),
            ),
          ] else ...[
            if (_isUrl)
              _ActionTile(
                icon: Icons.open_in_browser_rounded,
                label: 'Open URL',
                onTap: () => Navigator.pop(context, _ScanAction.openUrl),
              ),
            if (_isWifi) ...[
              _ActionTile(
                icon: Icons.wifi_password_rounded,
                label: 'Copy Wi-Fi password',
                onTap: () =>
                    Navigator.pop(context, _ScanAction.copyWifiPassword),
              ),
              _ActionTile(
                icon: Icons.settings_rounded,
                label: 'Connect to Wi-Fi',
                onTap: () =>
                    Navigator.pop(context, _ScanAction.connectWifi),
              ),
            ],
            if (_isPhone)
              _ActionTile(
                icon: Icons.call_rounded,
                label: 'Call',
                onTap: () => Navigator.pop(context, _ScanAction.callPhone),
              ),
            if (_isEmail)
              _ActionTile(
                icon: Icons.send_rounded,
                label: 'Send email',
                onTap: () => Navigator.pop(context, _ScanAction.sendEmail),
              ),
            if (_isGeoOrMap)
              _ActionTile(
                icon: Icons.directions_rounded,
                label: 'Open in Maps',
                onTap: () => Navigator.pop(context, _ScanAction.openMap),
              ),
            _ActionTile(
              icon: Icons.copy_rounded,
              label: 'Copy text',
              onTap: () => Navigator.pop(context, _ScanAction.copyText),
            ),
            _ActionTile(
              icon: Icons.share_rounded,
              label: 'Share',
              onTap: () => Navigator.pop(context, _ScanAction.shareText),
            ),
          ],
          _ActionTile(
            icon: Icons.qr_code_scanner_rounded,
            label: 'Scan again',
            onTap: () => Navigator.pop(context, _ScanAction.rescan),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        child: Row(
          children: [
            Icon(icon, size: 20, color: context.themeTextSecondary),
            const SizedBox(width: 14),
            Text(
              label,
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w500,
                color: context.themeTextPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
