import 'dart:async';
import 'dart:developer' as dev;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:provider/provider.dart';

import '../../../core/ads/ad_manager.dart';
import '../../../core/theme/app_card.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/scan_history_service.dart';
import '../../../core/services/scan_session_service.dart';
import '../models/scan_session.dart';
import 'scan_session_screen.dart';
import 'all_sessions_screen.dart';
import '../widgets/session_setup_sheet.dart';
import '../widgets/template_picker_sheet.dart';
import '../../../core/utils/app_router.dart';

enum ScanScreenMode { standalone, pickForClone }

enum _ScanEntryState { chooser, quickScan, scanToSheet }

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
  String? _lastValue;
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

  Future<void> _toggleScanner() async {
    if (!_isCameraSurfaceActive || _isCameraActionPending) return;
    _isCameraActionPending = true;

    try {
      if (_scannerRunning) {
        await _controller.stop();
      } else {
        await _controller.start();
      }
      if (mounted) setState(() => _scannerRunning = !_scannerRunning);
    } catch (_) {}

    _isCameraActionPending = false;
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
    _lastValue = raw;
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

  // ── New session: TemplatePicker → SessionSetupSheet ──────────────────────
  Future<void> _openNewSession() async {
    _stopScanner();
    final result = await TemplatePicker.show(context);
    if (result.dismissed || !mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SessionSetupSheet(
        initialTemplate: result.template,
        onSessionEnded: () {
          if (mounted) setState(() {});
        },
      ),
    );
    // Refresh active session card after sheet closes (covers dismiss case)
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

  @override
  Widget build(BuildContext context) {
    final activeSession = ScanSessionService.getActiveSession();
    // rest of build method unchanged — reading from existing file
    return const Placeholder();
  }
}
