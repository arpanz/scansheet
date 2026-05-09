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
  final ValueChanged<String>? onCloneEdit;
  final bool isActive;

  const ScanScreen({
    super.key,
    this.mode = ScanScreenMode.standalone,
    this.onCloneEdit,
    this.isActive = true,
  });

  const ScanScreen.pickForClone({super.key})
    : mode = ScanScreenMode.pickForClone,
      onCloneEdit = null,
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

      // Stop the live camera so analyzeImage() has exclusive access to ML Kit.
      // Do NOT start→stop cycle — that leaves the pipeline in a bad state.
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
        case _ScanAction.cloneEdit:
          if (widget.onCloneEdit != null) {
            widget.onCloneEdit!(raw);
            _snack('Moved to Create with scanned data.');
          }
          break;
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
      builder: (ctx) => _ScanResultSheet(
        raw: raw,
        type: type,
        isPickMode: _isPickMode,
        hasCloneEdit: widget.onCloneEdit != null,
      ),
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
      // ── Active session: prominent resume card ──
      final rowCount = ScanSessionService.getRowCount(activeSession.id);
      return [
        const SizedBox(height: 10),
        GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            _openSessionMode(activeSession);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: _kSheetGreen,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: _kSheetGreen.withValues(alpha: 0.30),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.20),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.table_chart_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
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
                      const SizedBox(height: 3),
                      Text(
                        '${activeSession.name} · $rowCount ${rowCount == 1 ? 'row' : 'rows'}',
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
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.20),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'Resume',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
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

    // ── No active session: feature discovery card ──
    return [
      const SizedBox(height: 10),
      GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          _openSessionMode(null);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: context.themeCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _kSheetGreen.withValues(alpha: 0.25)),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _kSheetGreen.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.table_chart_rounded,
                  color: _kSheetGreen,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
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
                    const SizedBox(height: 2),
                    Text(
                      'Scan codes → collect rows → export CSV/Excel',
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
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: _kSheetGreen.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'New Sheet',
                  style: TextStyle(
                    color: _kSheetGreen,
                    fontSize: 12,
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
                icon: const Icon(Icons.arrow_back),
                onPressed: () => _setEntryState(_ScanEntryState.chooser),
              )
            : null,
        title: Text(
          _isPickMode
              ? 'Scan to Clone'
              : switch (_entryState) {
                  _ScanEntryState.chooser => 'Smart Scanner',
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
                  : const Icon(Icons.image_search_rounded),
              onPressed: _isPickingImage ? null : _scanFromGallery,
            ),
          if (_entryState == _ScanEntryState.quickScan)
            IconButton(
              tooltip: 'Flash',
              icon: const Icon(Icons.flashlight_on_rounded),
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
              duration: const Duration(milliseconds: 380),
              transitionBuilder: (child, animation) {
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position:
                        Tween<Offset>(
                          begin: const Offset(0, 0.06), // subtle upward drift
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
          // Banner ad at the bottom — only shown in standalone mode (not pick-for-clone)
          if (!_isPickMode)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Center(child: AdManager.instance.getBannerAdWidget()),
            ),
        ],
      ),
    );
  }

  Widget _buildCamera() {
    return Padding(
      key: const ValueKey('quickScan'),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      child: Column(
        children: [
          Expanded(
            child: AppCard(
              padding: EdgeInsets.zero,
              borderRadius: 18,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: widget.isActive || _isPickMode
                    ? Stack(
                        children: [
                          MobileScanner(
                            controller: _controller,
                            onDetect: _onDetect,
                          ),
                          // Viewfinder overlay
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
                                  color: Colors.black.withValues(alpha: 0.55),
                                  child: Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          width: 56,
                                          height: 56,
                                          decoration: BoxDecoration(
                                            color: Colors.white.withValues(
                                              alpha: 0.15,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                            border: Border.all(
                                              color: Colors.white.withValues(
                                                alpha: 0.3,
                                              ),
                                            ),
                                          ),
                                          child: const Icon(
                                            Icons.play_arrow_rounded,
                                            color: Colors.white,
                                            size: 32,
                                          ),
                                        ),
                                        const SizedBox(height: 10),
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
            const SizedBox(height: 8),
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
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
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
                    letterSpacing: 0.5,
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
                    style: TextStyle(fontSize: 13, color: context.themeAccent),
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
                  'Jan',
                  'Feb',
                  'Mar',
                  'Apr',
                  'May',
                  'Jun',
                  'Jul',
                  'Aug',
                  'Sep',
                  'Oct',
                  'Nov',
                  'Dec',
                ];
                final dateStr =
                    '${months[s.createdAt.month - 1]} ${s.createdAt.day}';

                return InkWell(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    _openSessionMode(s);
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: context.themeCard,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: context.themeBorder.withValues(alpha: 0.5),
                      ),
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
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '$rowCount rows · $dateStr',
                                style: TextStyle(
                                  color: context.themeTextSecondary,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right,
                          color: context.themeTextSecondary,
                          size: 16,
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
              letterSpacing: -0.3,
              height: 1.25,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            'Choose a scan mode to get started',
            style: TextStyle(color: context.themeTextSecondary, fontSize: 13.5),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
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
          const SizedBox(height: 16),
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
        borderRadius: BorderRadius.circular(16),
        splashColor: accentColor.withValues(alpha: 0.08),
        highlightColor: accentColor.withValues(alpha: 0.04),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
          decoration: BoxDecoration(
            color: accentColor.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: accentColor.withValues(alpha: isDark ? 0.35 : 0.30),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: accentColor.withValues(alpha: isDark ? 0.08 : 0.05),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
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
                        fontSize: 16.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
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
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          for (int i = 0; i < stepIcons.length; i++) ...[
                            Icon(
                              stepIcons[i],
                              size: 14,
                              color: accentColor.withValues(alpha: 0.8),
                            ),
                            if (i < stepIcons.length - 1)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                child: Icon(
                                  Icons.arrow_forward_rounded,
                                  size: 12,
                                  color: context.themeTextSecondary.withValues(
                                    alpha: 0.4,
                                  ),
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
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.arrow_forward_rounded,
                  color: accentColor,
                  size: 15,
                ),
              ),
            ],
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
    duration: const Duration(milliseconds: 500),
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
        scale: Tween<double>(begin: 0.96, end: 1.0).animate(_anim),
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.06),
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
  final bool hasCloneEdit;

  const _ScanResultSheet({
    required this.raw,
    required this.type,
    required this.isPickMode,
    required this.hasCloneEdit,
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
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: context.themeBorder,
                    borderRadius: BorderRadius.circular(100),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  _typeIconBox(context),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _typeLabel(),
                          style: Theme.of(context).textTheme.titleMedium
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
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _buildContentCard(context),
              const SizedBox(height: 16),
              Divider(color: context.themeBorder, height: 1),
              const SizedBox(height: 16),
              Text(
                'ACTIONS',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: context.themeTextSecondary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 10),
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
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(icon, color: color, size: 24),
    );
  }

  (IconData, Color) _typeIconAndColor() {
    return switch (type) {
      'url' => (Icons.link_rounded, const Color(0xFF1E5BEA)),
      'wifi' => (Icons.wifi_rounded, const Color(0xFF16A34A)),
      'vcard' => (Icons.person_rounded, const Color(0xFF9333EA)),
      'email' => (Icons.email_rounded, const Color(0xFFEA4335)),
      'phone' => (Icons.phone_rounded, const Color(0xFF16A34A)),
      'sms' => (Icons.sms_rounded, const Color(0xFF0891B2)),
      'geo' => (Icons.location_on_rounded, const Color(0xFFF59E0B)),
      _ => (Icons.text_fields_rounded, const Color(0xFF64748B)),
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
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.themeBorder),
      ),
      child: SelectableText(
        raw,
        style: TextStyle(
          color: type == 'url' ? context.themeAccent : context.themeTextPrimary,
          fontSize: 13,
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
        border: Border.all(color: context.themeBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            decoration: BoxDecoration(
              color: avatarColor.withValues(alpha: 0.07),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: avatarColor.withValues(alpha: 0.18),
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
                    color: const Color(0xFFEA4335),
                    label: 'Email',
                    value: email,
                  ),
                if (url.isNotEmpty)
                  _ContactFieldTile(
                    icon: Icons.link_rounded,
                    color: const Color(0xFF1E5BEA),
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
                    color: const Color(0xFF64748B),
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
          actions.add((
            label: 'Copy Link',
            icon: Icons.copy_rounded,
            action: _ScanAction.copyText,
            primary: false,
          ));
          actions.add((
            label: 'Share',
            icon: Icons.share_rounded,
            action: _ScanAction.shareText,
            primary: false,
          ));
        case 'wifi':
          actions.add((
            label: 'Copy Password',
            icon: Icons.password_rounded,
            action: _ScanAction.copyWifiPassword,
            primary: true,
          ));
          actions.add((
            label: 'Wi-Fi Settings',
            icon: Icons.settings_rounded,
            action: _ScanAction.connectWifi,
            primary: false,
          ));
          actions.add((
            label: 'Copy Raw',
            icon: Icons.copy_all_rounded,
            action: _ScanAction.copyText,
            primary: false,
          ));
        case 'vcard':
          actions.add((
            label: 'Copy Full Text',
            icon: Icons.copy_rounded,
            action: _ScanAction.copyText,
            primary: true,
          ));
          actions.add((
            label: 'Share Contact',
            icon: Icons.share_rounded,
            action: _ScanAction.shareText,
            primary: false,
          ));
        case 'email':
          actions.add((
            label: 'Send Email',
            icon: Icons.send_rounded,
            action: _ScanAction.sendEmail,
            primary: true,
          ));
          actions.add((
            label: 'Copy Address',
            icon: Icons.copy_rounded,
            action: _ScanAction.copyText,
            primary: false,
          ));
        case 'phone':
          actions.add((
            label: 'Call',
            icon: Icons.call_rounded,
            action: _ScanAction.callPhone,
            primary: true,
          ));
          actions.add((
            label: 'Copy Number',
            icon: Icons.copy_rounded,
            action: _ScanAction.copyText,
            primary: false,
          ));
          actions.add((
            label: 'Share',
            icon: Icons.share_rounded,
            action: _ScanAction.shareText,
            primary: false,
          ));
        case 'sms':
          actions.add((
            label: 'Open SMS',
            icon: Icons.sms_rounded,
            action: _ScanAction.sendEmail,
            primary: true,
          ));
          actions.add((
            label: 'Copy',
            icon: Icons.copy_rounded,
            action: _ScanAction.copyText,
            primary: false,
          ));
        case 'geo':
          actions.add((
            label: 'Open in Maps',
            icon: Icons.map_rounded,
            action: _ScanAction.openMap,
            primary: true,
          ));
          actions.add((
            label: 'Copy Coordinates',
            icon: Icons.copy_rounded,
            action: _ScanAction.copyText,
            primary: false,
          ));
        default:
          actions.add((
            label: 'Copy Text',
            icon: Icons.copy_rounded,
            action: _ScanAction.copyText,
            primary: true,
          ));
          actions.add((
            label: 'Share',
            icon: Icons.share_rounded,
            action: _ScanAction.shareText,
            primary: false,
          ));
      }
      if (!isPickMode && hasCloneEdit) {
        actions.add((
          label: 'Clone / Edit',
          icon: Icons.edit_rounded,
          action: _ScanAction.cloneEdit,
          primary: false,
        ));
      }
      actions.add((
        label: 'Rescan',
        icon: Icons.qr_code_scanner_rounded,
        action: _ScanAction.rescan,
        primary: false,
      ));
    }

    final primaryActions = actions.where((a) => a.primary).toList();
    final secondaryActions = actions.where((a) => !a.primary).toList();

    return Column(
      children: [
        ...primaryActions.map(
          (a) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => Navigator.pop(context, a.action),
                icon: Icon(a.icon, size: 17),
                label: Text(a.label),
                style: FilledButton.styleFrom(
                  backgroundColor: context.themeAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (secondaryActions.isNotEmpty) ...[
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: secondaryActions
                .map(
                  (a) => ActionChip(
                    avatar: Icon(a.icon, size: 15),
                    label: Text(a.label),
                    onPressed: () => Navigator.pop(context, a.action),
                    backgroundColor: context.themeSurface,
                    side: BorderSide(color: context.themeBorder),
                    labelStyle: TextStyle(
                      fontSize: 12,
                      color: context.themeTextPrimary,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ],
    );
  }
}

// ── Contact field tile ────────────────────────────────────────────────────────
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
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: () async {
          await Clipboard.setData(ClipboardData(text: value));
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('$label copied'),
                duration: const Duration(seconds: 1),
              ),
            );
          }
        },
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.15)),
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
                        letterSpacing: 0.5,
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

// ── Shared helper widgets ─────────────────────────────────────────────────────
class _InfoCard extends StatelessWidget {
  final List<Widget> children;
  const _InfoCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.themeSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.themeBorder),
      ),
      child: Column(
        children: [
          for (int i = 0; i < children.length; i++) ...[
            children[i],
            if (i < children.length - 1)
              Divider(height: 16, color: context.themeBorder),
          ],
        ],
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: context.themeTextSecondary),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  color: context.themeTextSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                value,
                style: TextStyle(fontSize: 13, color: context.themeTextPrimary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

enum _ScanAction {
  rescan,
  useForClone,
  cloneEdit,
  openUrl,
  copyText,
  copyWifiPassword,
  connectWifi,
  callPhone,
  sendEmail,
  openMap,
  shareText,
}

// ─────────────────────────────────────────────────────────────────────────────
// Scanner viewfinder overlay — dims edges, clear center cutout, corner brackets
// ─────────────────────────────────────────────────────────────────────────────

class _ScannerOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double cutoutSize = size.shortestSide * 0.65;
    final double left = (size.width - cutoutSize) / 2;
    final double top = (size.height - cutoutSize) / 2;
    final cutoutRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(left, top, cutoutSize, cutoutSize),
      const Radius.circular(16),
    );

    // Dim the area outside the cutout
    final bgPaint = Paint()..color = const Color(0x88000000);
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(cutoutRect)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, bgPaint);

    // Corner brackets
    const double bracketLen = 24;
    const double bracketThickness = 3;
    final bracketPaint = Paint()
      ..color = const Color(0xFF16A34A)
      ..strokeWidth = bracketThickness
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final double r = 16; // corner radius
    final double x1 = left;
    final double y1 = top;
    final double x2 = left + cutoutSize;
    final double y2 = top + cutoutSize;

    // Top-left
    canvas.drawPath(
      Path()
        ..moveTo(x1, y1 + bracketLen)
        ..lineTo(x1, y1 + r)
        ..quadraticBezierTo(x1, y1, x1 + r, y1)
        ..lineTo(x1 + bracketLen, y1),
      bracketPaint,
    );
    // Top-right
    canvas.drawPath(
      Path()
        ..moveTo(x2 - bracketLen, y1)
        ..lineTo(x2 - r, y1)
        ..quadraticBezierTo(x2, y1, x2, y1 + r)
        ..lineTo(x2, y1 + bracketLen),
      bracketPaint,
    );
    // Bottom-left
    canvas.drawPath(
      Path()
        ..moveTo(x1, y2 - bracketLen)
        ..lineTo(x1, y2 - r)
        ..quadraticBezierTo(x1, y2, x1 + r, y2)
        ..lineTo(x1 + bracketLen, y2),
      bracketPaint,
    );
    // Bottom-right
    canvas.drawPath(
      Path()
        ..moveTo(x2 - bracketLen, y2)
        ..lineTo(x2 - r, y2)
        ..quadraticBezierTo(x2, y2, x2, y2 - r)
        ..lineTo(x2, y2 - bracketLen),
      bracketPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
