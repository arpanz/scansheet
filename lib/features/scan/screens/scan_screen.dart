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
    _entryState = _isPickMode
        ? _ScanEntryState.quickScan
        : _ScanEntryState.chooser;
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
      final BarcodeCapture? capture = await _controller.analyzeImage(
        picked.path,
      );

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
          _snack('Open Settings → Wi-Fi to connect manually.', isError: false);
          break;
        case _ScanAction.callPhone:
          final phone = raw.startsWith('tel:') ? raw : 'tel:${raw.trim()}';
          final uri = Uri.tryParse(phone);
          if (uri != null) await launchUrl(uri);
          break;
        case _ScanAction.sendEmail:
          final email = raw.startsWith('mailto:') ? raw : 'mailto:$raw';
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
        backgroundColor: isError ? context.themeError : context.themeAccent,
      ),
    );
  }

  void _openSessionMode(ScanSession? activeSession) {
    _stopScanner();
    if (activeSession != null) {
      Navigator.push(
        context,
        FadeSlideRoute(page: ScanSessionScreen(session: activeSession)),
      ).then((_) => setState(() {}));
    } else {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const SessionSetupSheet(),
      ).then((_) => setState(() {}));
    }
  }

  List<Widget> _buildSessionCard(ScanSession? activeSession) {
    if (activeSession != null) {
      final rowCount = ScanSessionService.getRowCount(activeSession.id);
      return [
        const SizedBox(height: 10),
        GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            _openSessionMode(activeSession);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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
          _openSessionMode(null);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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
                      'Scan to Spreadsheet',
                      style: TextStyle(
                        color: context.themeTextPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Scan codes \u00b7 collect rows \u00b7 export CSV/Excel',
                      style: TextStyle(
                        color: context.themeTextSecondary,
                        fontSize: 12,
                      ),
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
                  color: _kSheetGreen.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'New Sheet',
                  style: TextStyle(
                    color: _kSheetGreen,
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

  @override
  Widget build(BuildContext context) {
    final activeSession = _isPickMode
        ? null
        : ScanSessionService.getActiveSession();

    return Scaffold(
      appBar: AppBar(
        leading: (!_isPickMode && _entryState != _ScanEntryState.chooser)
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => _setEntryState(_ScanEntryState.chooser),
              )
            : null,
        title: Text(
          _isPickMode
              ? 'Scan to Clone'
              : switch (_entryState) {
                  _ScanEntryState.chooser => 'Scan',
                  _ScanEntryState.quickScan => 'Quick Scan',
                  _ScanEntryState.scanToSheet => 'Scan to Sheet',
                },
        ),
        actions: [
          if (!_isPickMode && _entryState == _ScanEntryState.quickScan)
            IconButton(
              tooltip: 'Scan from Gallery',
              icon: _isPickingImage
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.image_rounded),
              onPressed: _isPickingImage ? null : _scanFromGallery,
            ),
          if (_entryState == _ScanEntryState.quickScan)
            IconButton(
              tooltip: 'Flash',
              icon: const Icon(Icons.flash_on_rounded),
              onPressed: _isCameraSurfaceActive
                  ? _controller.toggleTorch
                  : null,
            ),
          if (_isPickMode || _entryState == _ScanEntryState.chooser)
            IconButton(
              tooltip: 'Toggle Theme',
              icon: Icon(
                Theme.of(context).brightness == Brightness.dark
                    ? Icons.light_mode_rounded
                    : Icons.dark_mode_rounded,
              ),
              onPressed: () {
                HapticFeedback.selectionClick();
                Provider.of<ThemeProvider>(
                  context,
                  listen: false,
                ).toggleTheme();
              },
            ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 360),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.04),
                      end: Offset.zero,
                    ).animate(
                      CurvedAnimation(
                        parent: animation,
                        curve: Curves.easeOutCubic,
                      ),
                    ),
                    child: child,
                  ),
                );
              },
              child: switch (_entryState) {
                _ScanEntryState.chooser => _buildChooser(),
                _ScanEntryState.quickScan => _buildCamera(),
                _ScanEntryState.scanToSheet => _buildSheetMode(activeSession),
              },
            ),
          ),
          if (!_isPickMode)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Center(child: AdManager.instance.getBannerAdWidget()),
            ),
        ],
      ),
    );
  }

  Widget _buildCamera() {
    return Padding(
      key: const ValueKey('quickScan'),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: context.themeBorder.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: widget.isActive || _isPickMode
                    ? Stack(
                        children: [
                          MobileScanner(
                            controller: _controller,
                            onDetect: _onDetect,
                          ),
                          if (_scannerRunning)
                            Positioned.fill(
                              child: CustomPaint(
                                painter: _ScannerOverlayPainter(),
                              ),
                            ),
                          if (!_scannerRunning)
                            Positioned.fill(
                              child: GestureDetector(
                                onTap: _toggleScanner,
                                child: Container(
                                  color: Colors.black.withValues(alpha: 0.5),
                                  child: Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          width: 60,
                                          height: 60,
                                          decoration: BoxDecoration(
                                            color: Colors.white.withValues(
                                              alpha: 0.12,
                                            ),
                                            borderRadius:
                                                BorderRadius.circular(16),
                                            border: Border.all(
                                              color: Colors.white.withValues(
                                                alpha: 0.2,
                                              ),
                                            ),
                                          ),
                                          child: const Icon(
                                            Icons.play_arrow_rounded,
                                            color: Colors.white,
                                            size: 34,
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        const Text(
                                          'Tap to resume scanning',
                                          style: TextStyle(
                                            color: Colors.white70,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      )
                    : Center(
                        child: Text(
                          'Open Scan tab to enable camera.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: context.themeTextSecondary),
                        ),
                      ),
              ),
            ),
          ),
          if (_lastValue != null) ...[
            const SizedBox(height: 10),
            Text(
              'Last: $_lastValue',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: context.themeTextSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSheetMode(ScanSession? activeSession) {
    final allSessions = ScanSessionService.getAllSessions();
    final pastSessions = allSessions.where((s) => !s.isActive).toList();
    final displaySessions = pastSessions.take(10).toList();

    return SingleChildScrollView(
      key: const ValueKey('sheet'),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ..._buildSessionCard(activeSession),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  'My Sheets',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: context.themeTextSecondary,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              if (pastSessions.length > 10)
                TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      FadeSlideRoute(page: const AllSessionsScreen()),
                    ).then((_) => setState(() {}));
                  },
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    'View All',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: context.themeAccent,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (pastSessions.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text(
                  'No past sheets yet.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: context.themeTextSecondary,
                  ),
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              itemCount: displaySessions.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final s = displaySessions[index];
                final rowCount = ScanSessionService.getRowCount(s.id);
                const months = [
                  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
                ];
                final dateStr =
                    '${months[s.createdAt.month - 1]} ${s.createdAt.day}';

                return AppCard(
                  borderRadius: 14,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    _openSessionMode(s);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.table_view_rounded,
                          color: context.themeTextSecondary,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                s.name,
                                style: TextStyle(
                                  color: context.themeTextPrimary,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '$rowCount rows \u00b7 $dateStr',
                                style: TextStyle(
                                  color: context.themeTextSecondary,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: context.themeTextSecondary,
                          size: 18,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildChooser() {
    return Padding(
      key: const ValueKey('chooser'),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 8),
          Text(
            'What would you\nlike to do?',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
              height: 1.2,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Choose a scan mode to get started',
            style: TextStyle(
              color: context.themeTextSecondary,
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 36),
          _StaggeredCard(
            delayMs: 0,
            child: _buildChooserCard(
              title: 'Quick Scan',
              subtitle: 'Scan once, see result instantly',
              icon: Icons.qr_code_scanner_rounded,
              accentColor: context.themeAccent,
              stepIcons: const [
                Icons.camera_alt_rounded,
                Icons.bolt_rounded,
                Icons.content_copy_rounded,
              ],
              onTap: () {
                HapticFeedback.selectionClick();
                _setEntryState(_ScanEntryState.quickScan);
              },
            ),
          ),
          const SizedBox(height: 14),
          _StaggeredCard(
            delayMs: 80,
            child: _buildChooserCard(
              title: 'Scan to Sheet',
              subtitle: 'Collect scans into a spreadsheet',
              icon: Icons.table_chart_rounded,
              accentColor: _kSheetGreen,
              stepIcons: const [
                Icons.camera_alt_rounded,
                Icons.list_alt_rounded,
                Icons.file_download_rounded,
              ],
              onTap: () {
                HapticFeedback.selectionClick();
                _setEntryState(_ScanEntryState.scanToSheet);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChooserCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
    required VoidCallback onTap,
    List<IconData> stepIcons = const [],
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        splashColor: accentColor.withValues(alpha: 0.08),
        highlightColor: accentColor.withValues(alpha: 0.04),
        child: Ink(
          padding: const EdgeInsets.all(1),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              colors: [
                accentColor.withValues(alpha: isDark ? 0.3 : 0.25),
                accentColor.withValues(alpha: isDark ? 0.05 : 0.03),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF121215)
                  : const Color(0xFFF8F8FB),
              borderRadius: BorderRadius.circular(17),
            ),
            child: Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: accentColor, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: context.themeTextPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: context.themeTextSecondary,
                          fontSize: 13,
                        ),
                      ),
                      if (stepIcons.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            for (int i = 0; i < stepIcons.length; i++) ...[
                              Icon(
                                stepIcons[i],
                                size: 15,
                                color: accentColor.withValues(alpha: 0.7),
                              ),
                              if (i < stepIcons.length - 1)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                  ),
                                  child: Icon(
                                    Icons.arrow_forward_rounded,
                                    size: 12,
                                    color: context.themeTextSecondary
                                        .withValues(alpha: 0.4),
                                  ),
                                ),
                            ],
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.arrow_forward_rounded,
                    color: accentColor,
                    size: 18,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StaggeredCard extends StatefulWidget {
  final Widget child;
  final int delayMs;
  const _StaggeredCard({required this.child, required this.delayMs});

  @override
  State<_StaggeredCard> createState() => _StaggeredCardState();
}

class _StaggeredCardState extends State<_StaggeredCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 480),
  );
  late final Animation<double> _anim = CurvedAnimation(
    parent: _ctrl,
    curve: Curves.easeOutCubic,
  );

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: widget.delayMs), () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _anim,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.97, end: 1.0).animate(_anim),
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.05),
            end: Offset.zero,
          ).animate(_anim),
          child: widget.child,
        ),
      ),
    );
  }
}

// ── Rich Result Bottom Sheet Widget ──────────────────────────────────────────
class _ScanResultSheet extends StatelessWidget {
  final String raw;
  final String type;
  final bool isPickMode;

  const _ScanResultSheet({
    required this.raw,
    required this.type,
    required this.isPickMode,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.themeCard,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: context.themeTextSecondary.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(100),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  _typeIconBox(context),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _typeLabel(),
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(
                                color: context.themeTextPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        Text(
                          isPickMode ? 'Scan to Clone' : 'Scan Result',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: context.themeTextSecondary),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context, _ScanAction.rescan),
                    icon: Icon(
                      Icons.close_rounded,
                      color: context.themeTextSecondary,
                      size: 20,
                    ),
                    style: IconButton.styleFrom(
                      backgroundColor: context.themeSurface,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildContentCard(context),
              const SizedBox(height: 18),
              Divider(color: context.themeBorder, height: 1),
              const SizedBox(height: 16),
              Text(
                'ACTIONS',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: context.themeTextSecondary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 12),
              _buildActions(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _typeIconBox(BuildContext context) {
    final (icon, color) = _typeIconAndColor();
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(icon, color: color, size: 24),
    );
  }

  (IconData, Color) _typeIconAndColor() {
    return switch (type) {
      'url' => (Icons.link_rounded, const Color(0xFF3B82F6)),
      'wifi' => (Icons.wifi_rounded, const Color(0xFF16A34A)),
      'vcard' => (Icons.person_rounded, const Color(0xFF8B5CF6)),
      'email' => (Icons.email_rounded, const Color(0xFFEF4444)),
      'phone' => (Icons.phone_rounded, const Color(0xFF16A34A)),
      'sms' => (Icons.sms_rounded, const Color(0xFF06B6D4)),
      'geo' => (Icons.location_on_rounded, const Color(0xFFF59E0B)),
      _ => (Icons.text_fields_rounded, const Color(0xFF6B7280)),
    };
  }

  String _typeLabel() {
    return switch (type) {
      'url' => 'Web Link',
      'wifi' => 'Wi-Fi Network',
      'vcard' => 'Contact / vCard',
      'email' => 'Email Address',
      'phone' => 'Phone Number',
      'sms' => 'SMS Message',
      'geo' => 'Location',
      _ => 'Plain Text',
    };
  }

  Widget _buildContentCard(BuildContext context) {
    if (type == 'wifi') return _buildWifiCard(context);
    if (type == 'vcard') return _buildVcardCard(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.themeSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: context.themeBorder.withValues(alpha: 0.5),
        ),
      ),
      child: SelectableText(
        raw,
        style: TextStyle(
          color: type == 'url' ? context.themeAccent : context.themeTextPrimary,
          fontSize: 13.5,
          height: 1.5,
        ),
      ),
    );
  }

  Widget _buildWifiCard(BuildContext context) {
    final ssid = RegExp(r'S:(.*?);').firstMatch(raw)?.group(1) ?? '';
    final password = RegExp(r';P:(.*?);').firstMatch(raw)?.group(1) ?? '';
    final security = RegExp(r'T:(.*?);').firstMatch(raw)?.group(1) ?? 'WPA';
    return _InfoCard(
      children: [
        _InfoRow(icon: Icons.wifi_rounded, label: 'Network', value: ssid),
        if (password.isNotEmpty)
          _InfoRow(
            icon: Icons.lock_rounded,
            label: 'Password',
            value: password,
          ),
        _InfoRow(
          icon: Icons.security_rounded,
          label: 'Security',
          value: security,
        ),
      ],
    );
  }

  Widget _buildVcardCard(BuildContext context) {
    String getValue(String mecardKey, String vcardKey) {
      final meMatch = RegExp('$mecardKey:(.*?);').firstMatch(raw);
      if (meMatch != null) return meMatch.group(1)?.trim() ?? '';
      final vcMatch = RegExp(
        '$vcardKey[^:]*:(.*?)(?:\r?\n|\$)',
        caseSensitive: false,
      ).firstMatch(raw);
      return vcMatch?.group(1)?.trim() ?? '';
    }

    final name = getValue('N', 'FN');
    final phone = getValue('TEL', 'TEL');
    final email = getValue('EMAIL', 'EMAIL');
    final org = getValue('ORG', 'ORG');
    final url = getValue('URL', 'URL');
    final address = getValue('ADR', 'ADR');
    final note = getValue('NOTE', 'NOTE');

    final initials = name
        .trim()
        .split(RegExp(r'\s+'))
        .take(2)
        .map((w) => w.isNotEmpty ? w[0].toUpperCase() : '')
        .join();

    final (_, avatarColor) = _typeIconAndColor();

    return Container(
      decoration: BoxDecoration(
        color: context.themeSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: context.themeBorder.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            decoration: BoxDecoration(
              color: avatarColor.withValues(alpha: 0.06),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: avatarColor.withValues(alpha: 0.15),
                  child: Text(
                    initials.isEmpty ? '?' : initials,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: avatarColor,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name.isEmpty ? 'Unknown Contact' : name,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: context.themeTextPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      if (org.isNotEmpty)
                        Text(
                          org,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: context.themeTextSecondary),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
            child: Column(
              children: [
                if (phone.isNotEmpty)
                  _ContactFieldTile(
                    icon: Icons.phone_rounded,
                    color: const Color(0xFF16A34A),
                    label: 'Phone',
                    value: phone,
                  ),
                if (email.isNotEmpty)
                  _ContactFieldTile(
                    icon: Icons.email_rounded,
                    color: const Color(0xFFEF4444),
                    label: 'Email',
                    value: email,
                  ),
                if (url.isNotEmpty)
                  _ContactFieldTile(
                    icon: Icons.link_rounded,
                    color: const Color(0xFF3B82F6),
                    label: 'Website',
                    value: url,
                  ),
                if (address.isNotEmpty)
                  _ContactFieldTile(
                    icon: Icons.location_on_rounded,
                    color: const Color(0xFFF59E0B),
                    label: 'Address',
                    value: address,
                  ),
                if (note.isNotEmpty)
                  _ContactFieldTile(
                    icon: Icons.notes_rounded,
                    color: const Color(0xFF6B7280),
                    label: 'Note',
                    value: note,
                  ),
                if (phone.isEmpty &&
                    email.isEmpty &&
                    url.isEmpty &&
                    address.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: SelectableText(
                      raw,
                      style: TextStyle(
                        fontSize: 12,
                        color: context.themeTextPrimary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions(BuildContext context) {
    final actions =
        <({String label, IconData icon, _ScanAction action, bool primary})>[];

    if (isPickMode) {
      actions.add((
        label: 'Use for Clone',
        icon: Icons.content_paste_rounded,
        action: _ScanAction.useForClone,
        primary: true,
      ));
    } else {
      switch (type) {
        case 'url':
          actions.add((
            label: 'Open in Browser',
            icon: Icons.open_in_new_rounded,
            action: _ScanAction.openUrl,
            primary: true,
          ));
          break;
        case 'wifi':
          actions.add((
            label: 'Copy Password',
            icon: Icons.key_rounded,
            action: _ScanAction.copyWifiPassword,
            primary: true,
          ));
          actions.add((
            label: 'Copy All',
            icon: Icons.copy_rounded,
            action: _ScanAction.copyText,
            primary: false,
          ));
          break;
        case 'vcard':
          actions.add((
            label: 'Copy',
            icon: Icons.copy_rounded,
            action: _ScanAction.copyText,
            primary: true,
          ));
          break;
        case 'email':
          actions.add((
            label: 'Compose Email',
            icon: Icons.send_rounded,
            action: _ScanAction.sendEmail,
            primary: true,
          ));
          break;
        case 'phone':
          actions.add((
            label: 'Call',
            icon: Icons.call_rounded,
            action: _ScanAction.callPhone,
            primary: true,
          ));
          break;
        case 'sms':
          actions.add((
            label: 'Copy',
            icon: Icons.copy_rounded,
            action: _ScanAction.copyText,
            primary: true,
          ));
          break;
        case 'geo':
          actions.add((
            label: 'Open Map',
            icon: Icons.map_rounded,
            action: _ScanAction.openMap,
            primary: true,
          ));
          break;
        default:
          actions.add((
            label: 'Copy',
            icon: Icons.copy_rounded,
            action: _ScanAction.copyText,
            primary: true,
          ));
          break;
      }

      if (!actions.any((a) => a.action == _ScanAction.copyText) &&
          type != 'wifi') {
        actions.add((
          label: 'Copy',
          icon: Icons.copy_rounded,
          action: _ScanAction.copyText,
          primary: false,
        ));
      }
    }

    actions.add((
      label: 'Share',
      icon: Icons.share_rounded,
      action: _ScanAction.shareText,
      primary: false,
    ));

    return Wrap(spacing: 10, runSpacing: 10, children: [
      for (final a in actions)
        if (a.primary)
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, a.action),
            icon: Icon(a.icon, size: 18),
            label: Text(a.label),
          )
        else
          OutlinedButton.icon(
            onPressed: () => Navigator.pop(context, a.action),
            icon: Icon(a.icon, size: 18),
            label: Text(a.label),
          ),
    ]);
  }
}

// ── Shared result sheet widgets ───────────────────────────────────────────────
class _InfoCard extends StatelessWidget {
  final List<Widget> children;
  const _InfoCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: context.themeSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: context.themeBorder.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        children: children,
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: context.themeTextSecondary),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: context.themeTextSecondary,
                  letterSpacing: 0.3,
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  fontSize: 13.5,
                  color: context.themeTextPrimary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ContactFieldTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;

  const _ContactFieldTile({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () async {
          await Clipboard.setData(ClipboardData(text: value));
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('$label copied'),
                backgroundColor: context.themeSuccess,
                duration: const Duration(seconds: 1),
              ),
            );
          }
        },
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.12)),
          ),
          child: Row(
            children: [
              Icon(icon, size: 17, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: context.themeTextSecondary,
                        letterSpacing: 0.3,
                      ),
                    ),
                    Text(
                      value,
                      style: TextStyle(
                        fontSize: 13,
                        color: context.themeTextPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.copy_rounded,
                size: 14,
                color: context.themeTextSecondary.withValues(alpha: 0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Scanner overlay painter ───────────────────────────────────────────────────
class _ScannerOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cutoutSize = size.shortestSide * 0.72;
    final left = (size.width - cutoutSize) / 2;
    final top = (size.height - cutoutSize) / 2;
    final cutoutRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(left, top, cutoutSize, cutoutSize),
      const Radius.circular(18),
    );

    final bgPaint = Paint()..color = const Color(0x77000000);
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(cutoutRect)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, bgPaint);

    const double bracketLen = 28;
    final bracketPaint = Paint()
      ..color = const Color(0xFF22C55E)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final double r = 18;
    final double x1 = left, y1 = top;
    final double x2 = left + cutoutSize, y2 = top + cutoutSize;

    void drawCorner(double sx, double sy, double dx, double dy) {
      final p = Path()
        ..moveTo(sx, sy + dy)
        ..lineTo(sx, sy + r)
        ..quadraticBezierTo(sx, sy, sx + r, sy)
        ..lineTo(sx + dx, sy);
      canvas.drawPath(p, bracketPaint);
    }

    drawCorner(x1, y1, bracketLen, 0); // top-left (horizontal)
    drawCorner(x1, y1, 0, bracketLen); // top-left (vertical)

    drawCorner(x2, y1, -bracketLen, 0); // top-right (horizontal)
    drawCorner(x2, y1, 0, bracketLen); // top-right (vertical)

    drawCorner(x1, y2, bracketLen, 0); // bottom-left (horizontal)
    drawCorner(x1, y2, 0, -bracketLen); // bottom-left (vertical)

    drawCorner(x2, y2, -bracketLen, 0); // bottom-right (horizontal)
    drawCorner(x2, y2, 0, -bracketLen); // bottom-right (vertical)

    final hintPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.5)
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(left + 2, top + 2, cutoutSize - 4, cutoutSize - 4),
        const Radius.circular(16),
      ),
      hintPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

enum _ScanAction {
  copyText,
  openUrl,
  copyWifiPassword,
  connectWifi,
  callPhone,
  sendEmail,
  openMap,
  shareText,
  useForClone,
  rescan,
}
