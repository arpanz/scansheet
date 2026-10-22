// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/scan_history_service.dart';
import '../../../core/services/scanning_preferences.dart';
import '../../../core/theme/app_theme.dart';
import '../../shell/app_shell.dart';
import '../../../core/widgets/ss.dart';

class ReadCodeScreen extends StatefulWidget {
  const ReadCodeScreen({super.key});

  @override
  State<ReadCodeScreen> createState() => _ReadCodeScreenState();
}

class _ReadCodeScreenState extends State<ReadCodeScreen> {
  late final MobileScannerController _camera;
  final ImagePicker _imagePicker = ImagePicker();
  late final bool _vibrate;
  bool _busy = false;
  bool _torch = false;
  bool _pickingImage = false;
  double _zoom = 1;

  @override
  void initState() {
    super.initState();
    final prefs = context.read<ScanningPreferences>();
    _vibrate = prefs.vibrateEnabled;
    _torch = prefs.torchDefault;
    _camera = MobileScannerController(
      torchEnabled: _torch,
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: CameraFacing.back,
      formats: [BarcodeFormat.all],
    );
  }

  @override
  void dispose() {
    _camera.dispose();
    super.dispose();
  }

  Future<void> _detected(BarcodeCapture capture) async {
    if (_busy) return;
    final raw = capture.barcodes
        .map((barcode) => barcode.rawValue?.trim() ?? '')
        .firstWhere((value) => value.isNotEmpty, orElse: () => '');
    if (raw.isNotEmpty) await _handleValue(raw);
  }

  Future<void> _scanFromGallery() async {
    if (_pickingImage || _busy) return;
    setState(() => _pickingImage = true);
    _busy = true;
    try {
      final picked = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 100,
        maxWidth: 2048,
      );
      if (picked == null) {
        _busy = false;
        return;
      }
      await _camera.stop();
      final capture = await _camera.analyzeImage(picked.path);
      if (!mounted) return;
      final raw =
          capture?.barcodes
              .map((barcode) => (barcode.rawValue ?? '').trim())
              .firstWhere((value) => value.isNotEmpty, orElse: () => '') ??
          '';
      if (raw.isEmpty) {
        showSsToast(context, 'No QR / barcode found in the selected image.');
        _busy = false;
        await _camera.start();
      } else {
        _busy = false;
        await _handleValue(raw);
      }
    } catch (error) {
      if (mounted) showSsToast(context, 'Error reading image: $error');
      _busy = false;
      await _camera.start();
    } finally {
      if (mounted) setState(() => _pickingImage = false);
    }
  }

  Future<void> _handleValue(String raw) async {
    if (_busy) return;
    _busy = true;
    await _camera.stop();
    if (_vibrate) HapticFeedback.mediumImpact();
    await ScanHistoryService.save(
      ScanEntry(
        raw: raw,
        type: ScanEntry.detectType(raw),
        scannedAt: DateTime.now(),
      ),
    );
    if (!mounted) return;
    final action = await _showResultSheet(raw);
    if (!mounted) return;
    if (action == _ResultAction.rescan) {
      _busy = false;
      await _camera.start();
      return;
    }
    await _performAction(action, raw);
    if (mounted) {
      _busy = false;
      await _camera.start();
    }
  }

  Future<void> _performAction(_ResultAction action, String raw) async {
    switch (action) {
      case _ResultAction.openUrl:
      case _ResultAction.openMap:
        final uri = Uri.tryParse(raw);
        if (uri != null)
          await launchUrl(uri, mode: LaunchMode.externalApplication);
      case _ResultAction.copyText:
        await Clipboard.setData(ClipboardData(text: raw));
        if (mounted) showSsToast(context, 'Copied to clipboard.');
      case _ResultAction.copyWifiPassword:
        final password = RegExp(r';P:(.*?);').firstMatch(raw)?.group(1);
        if (password == null || password.isEmpty) {
          if (mounted) showSsToast(context, 'No Wi-Fi password found.');
        } else {
          await Clipboard.setData(ClipboardData(text: password));
          if (mounted) showSsToast(context, 'Wi-Fi password copied.');
        }
      case _ResultAction.connectWifi:
        if (mounted)
          showSsToast(context, 'Open Settings → Wi-Fi to connect manually.');
      case _ResultAction.callPhone:
        final uri = Uri.tryParse(
          raw.startsWith('tel:') ? raw : 'tel:${raw.trim()}',
        );
        if (uri != null) await launchUrl(uri);
      case _ResultAction.sendEmail:
        final uri = Uri.tryParse(
          raw.startsWith('mailto:') ? raw : 'mailto:$raw',
        );
        if (uri != null) await launchUrl(uri);
      case _ResultAction.shareText:
        await SharePlus.instance.share(ShareParams(text: raw));
      case _ResultAction.rescan:
        break;
    }
  }

  Future<_ResultAction> _showResultSheet(String raw) async {
    final action = await showSsSheet<_ResultAction>(
      context,
      builder: (context) => _CodeResultSheet(raw: raw),
    );
    return action ?? _ResultAction.rescan;
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppTheme.darkTheme,
      child: Scaffold(
        backgroundColor: SsColors.night,
        body: Stack(
          fit: StackFit.expand,
          children: [
            MobileScanner(controller: _camera, onDetect: _detected),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x660B0F0D),
                    Colors.transparent,
                    Color(0x990B0F0D),
                  ],
                  stops: [0, .45, 1],
                ),
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Row(
                      children: [
                        SsIconButton(
                          LucideIcons.x,
                          tooltip: 'Close',
                          color: Colors.white,
                          background: Colors.white.withValues(alpha: .14),
                          onPressed: () => Navigator.pop(context),
                        ),
                        const Spacer(),
                        Container(
                          height: 40,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: .14),
                            borderRadius: BorderRadius.circular(22),
                          ),
                          child: Text(
                            'Read a code',
                            style: SsText.sans(
                              size: 14,
                              weight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const Spacer(),
                        SsIconButton(
                          _torch
                              ? LucideIcons.flashlight
                              : LucideIcons.flashlight,
                          tooltip: 'Torch',
                          color: _torch ? SsColors.brandInk : Colors.white,
                          background: _torch
                              ? SsColors.brandLime
                              : Colors.white.withValues(alpha: .14),
                          onPressed: () async {
                            setState(() => _torch = !_torch);
                            await _camera.toggleTorch();
                          },
                        ),
                      ],
                    ),
                  ),
                  const Spacer(flex: 2),
                  SizedBox(
                    width: 270,
                    height: 150,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(
                                color: SsColors.brandLime.withValues(alpha: .5),
                                width: 1,
                              ),
                            ),
                          ),
                        ),
                        for (final corner in const [
                          (true, true),
                          (true, false),
                          (false, true),
                          (false, false),
                        ])
                          Positioned(
                            top: corner.$1 ? 0 : null,
                            bottom: corner.$1 ? null : 0,
                            left: corner.$2 ? 0 : null,
                            right: corner.$2 ? null : 0,
                            child: SsScanCorner(
                              top: corner.$1,
                              left: corner.$2,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 48),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [1.0, 2.0, 5.0].map((zoom) {
                      final selected = _zoom == zoom;
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: TextButton(
                          onPressed: () async {
                            setState(() => _zoom = zoom);
                            await _camera.setZoomScale(zoom);
                          },
                          style: TextButton.styleFrom(
                            minimumSize: const Size(44, 44),
                            backgroundColor: selected
                                ? Colors.white
                                : Colors.black.withValues(alpha: .35),
                            foregroundColor: selected
                                ? SsColors.light.ink
                                : Colors.white,
                            shape: const CircleBorder(),
                          ),
                          child: Text(
                            '${zoom.toInt()}x',
                            style: SsText.mono(
                              size: 13,
                              weight: FontWeight.w600,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const Spacer(flex: 2),
                  Theme(data: AppTheme.lightTheme, child: const _BottomPanel()),
                ],
              ),
            ),
            if (_pickingImage)
              const Center(
                child: CircularProgressIndicator(color: SsColors.brandLime),
              ),
          ],
        ),
      ),
    );
  }
}

class _BottomPanel extends StatelessWidget {
  const _BottomPanel();

  @override
  Widget build(BuildContext context) {
    final c = SsColors.light;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        16,
        10,
        16,
        34 + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: BoxDecoration(
        color: c.paper,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 5,
            decoration: BoxDecoration(
              color: c.strongBorder,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Point at any barcode or QR code',
            textAlign: TextAlign.center,
            style: SsText.sans(size: 15, weight: FontWeight.w600, color: c.ink),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: SsButton.secondary(
                  'From photo',
                  icon: LucideIcons.image,
                  onPressed: () => context
                      .findAncestorStateOfType<_ReadCodeScreenState>()
                      ?._scanFromGallery(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SsButton.secondary(
                  'History',
                  icon: LucideIcons.clock3,
                  onPressed: AppShell.showCodeHistory.fire,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

enum _ResultAction {
  openUrl,
  copyText,
  copyWifiPassword,
  connectWifi,
  callPhone,
  sendEmail,
  openMap,
  shareText,
  rescan,
}

class _CodeResultSheet extends StatelessWidget {
  final String raw;
  const _CodeResultSheet({required this.raw});

  bool get _url => raw.startsWith('http://') || raw.startsWith('https://');
  bool get _wifi => raw.startsWith('WIFI:');
  bool get _phone =>
      raw.startsWith('tel:') || RegExp(r'^\+?[0-9\s\-().]{7,}$').hasMatch(raw);
  bool get _email => raw.startsWith('mailto:') || raw.contains('@');
  bool get _map => raw.startsWith('geo:') || raw.startsWith('https://maps.');

  @override
  Widget build(BuildContext context) {
    final type = ScanEntry.detectType(raw).toUpperCase();
    final category = _url
        ? 'URL'
        : _wifi
        ? 'WI-FI'
        : _phone
        ? 'PHONE'
        : _email
        ? 'EMAIL'
        : _map
        ? 'MAP'
        : type;
    return Theme(
      data: AppTheme.lightTheme,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '$type · $category',
              style: SsText.eyebrow(color: context.ss.muted),
            ),
            const SizedBox(height: 12),
            SelectableText(
              raw,
              style: SsText.mono(size: 14, color: context.ss.ink),
              maxLines: 5,
            ),
            const SizedBox(height: 18),
            if (_url)
              _action(
                context,
                'Open link',
                LucideIcons.externalLink,
                _ResultAction.openUrl,
              ),
            if (_wifi) ...[
              _action(
                context,
                'Copy Wi-Fi password',
                LucideIcons.copy,
                _ResultAction.copyWifiPassword,
              ),
              _action(
                context,
                'Connect to Wi-Fi',
                LucideIcons.wifi,
                _ResultAction.connectWifi,
              ),
            ],
            if (_phone)
              _action(
                context,
                'Call',
                LucideIcons.phone,
                _ResultAction.callPhone,
              ),
            if (_email)
              _action(
                context,
                'Send email',
                LucideIcons.mail,
                _ResultAction.sendEmail,
              ),
            if (_map)
              _action(
                context,
                'Open in Maps',
                LucideIcons.mapPin,
                _ResultAction.openMap,
              ),
            _action(
              context,
              'Copy text',
              LucideIcons.copy,
              _ResultAction.copyText,
            ),
            _action(
              context,
              'Share',
              LucideIcons.share2,
              _ResultAction.shareText,
            ),
            const SizedBox(height: 8),
            SsButton.secondary(
              'Scan another',
              icon: LucideIcons.scanLine,
              onPressed: () => Navigator.pop(context, _ResultAction.rescan),
            ),
          ],
        ),
      ),
    );
  }

  Widget _action(
    BuildContext context,
    String label,
    IconData icon,
    _ResultAction result,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: SsButton.secondary(
      label,
      icon: icon,
      onPressed: () => Navigator.pop(context, result),
    ),
  );
}
