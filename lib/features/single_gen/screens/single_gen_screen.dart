import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';

import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/ads/ad_manager.dart';
import '../../../core/services/history_service.dart';
import '../../../core/utils/review_service.dart';

import '../../../core/theme/app_card.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/style/qr_style_profile.dart';
import '../../../core/style/qr_style_service.dart';
import '../../../core/utils/app_router.dart';
import '../../history/models/history_entry.dart';
import '../../scan/screens/scan_screen.dart';
import '../models/data_type.dart';
import '../models/generator_type.dart';
import '../models/logo_fit_mode.dart';
import '../models/logo_shape.dart';
import '../widgets/data_type_forms.dart';
import '../widgets/format_dropdown.dart';
import '../widgets/preview_card.dart';
import '../widgets/type_tab_row.dart';

class SingleGenScreen extends StatefulWidget {
  final ValueNotifier<String?>? cloneTextListenable;

  const SingleGenScreen({super.key, this.cloneTextListenable});

  @override
  State<SingleGenScreen> createState() => _SingleGenScreenState();
}

class _SingleGenScreenState extends State<SingleGenScreen> {
  final _textController = TextEditingController();
  final _previewKey = GlobalKey();
  Future<void> _savePrefsQueue = Future<void>.value();

  DataType _dataType = DataType.text;
  GeneratorType _genType = GeneratorType.qrCode;
  String _encodedData = '';
  bool _isSaving = false;

  /// Stored encoded data per non-text type so switching back preserves it.
  final Map<DataType, String> _encodedDataCache = {};

  Color _fgColor = Colors.black;
  Color _eyeColor = Colors.black;
  Color _bgColor = Colors.white;
  int _ecLevel = QrErrorCorrectLevel.M;
  Uint8List? _logoBytes;
  double _logoSize = 36;
  LogoShape _logoShape = LogoShape.square;
  LogoFitMode _logoFitMode = LogoFitMode.cover;
  double _logoZoom = 1.0;
  double _logoOffsetX = 0.0;
  double _logoOffsetY = 0.0;
  double _logoPadding = 4;
  bool _logoBgEnabled = true;
  QrEyeShape _eyeShape = QrEyeShape.square;
  QrDataModuleShape _moduleShape = QrDataModuleShape.square;
  bool _frameEnabled = false;
  double _frameThickness = 2;
  Color _frameColor = Colors.black;
  int _sectionTabIndex = 0;
  List<QrStyleProfile> _styleProfiles = const [];
  String _activeStyleProfileId = 'default';

  static const _ecLevels = [
    (label: 'L', value: QrErrorCorrectLevel.L),
    (label: 'M', value: QrErrorCorrectLevel.M),
    (label: 'Q', value: QrErrorCorrectLevel.Q),
    (label: 'H', value: QrErrorCorrectLevel.H),
  ];

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    widget.cloneTextListenable?.addListener(_onCloneTextRequested);
  }

  @override
  void didUpdateWidget(covariant SingleGenScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cloneTextListenable != widget.cloneTextListenable) {
      oldWidget.cloneTextListenable?.removeListener(_onCloneTextRequested);
      widget.cloneTextListenable?.addListener(_onCloneTextRequested);
    }
  }

  void _updateStyle(VoidCallback update) {
    setState(update);
    _queueSavePrefs();
  }

  void _queueSavePrefs() {
    _savePrefsQueue = _savePrefsQueue
        .then((_) => _savePrefs())
        .onError((error, stackTrace) {});
  }

  QrStyleProfile _buildCurrentStyleProfile({
    required String id,
    required String name,
  }) {
    return QrStyleProfile(
      id: id,
      name: name,
      foregroundArgb: _fgColor.toARGB32(),
      eyeArgb: _eyeColor.toARGB32(),
      backgroundArgb: _bgColor.toARGB32(),
      errorCorrectionLevel: _ecLevel,
      eyeShape: _eyeShape.name,
      moduleShape: _moduleShape.name,
      frameEnabled: _frameEnabled,
      frameThickness: _frameThickness,
      frameColorArgb: _frameColor.toARGB32(),
      logoBase64: _logoBytes == null ? null : base64Encode(_logoBytes!),
      logoSize: _logoSize,
      logoShape: _logoShape.name,
      logoFitMode: _logoFitMode.name,
      logoZoom: _logoZoom,
      logoOffsetX: _logoOffsetX,
      logoOffsetY: _logoOffsetY,
      logoPadding: _logoPadding,
      logoBgEnabled: _logoBgEnabled,
    );
  }

  void _applyStyleProfile(QrStyleProfile profile) {
    setState(() {
      _fgColor = Color(profile.foregroundArgb);
      _eyeColor = Color(profile.eyeArgb);
      _bgColor = Color(profile.backgroundArgb);
      _ecLevel = profile.errorCorrectionLevel;
      _eyeShape = QrEyeShape.values.firstWhere(
        (e) => e.name == profile.eyeShape,
        orElse: () => QrEyeShape.square,
      );
      _moduleShape = QrDataModuleShape.values.firstWhere(
        (e) => e.name == profile.moduleShape,
        orElse: () => QrDataModuleShape.square,
      );
      _frameEnabled = profile.frameEnabled;
      _frameThickness = profile.frameThickness;
      _frameColor = Color(profile.frameColorArgb);
      _logoSize = profile.logoSize;
      _logoShape = LogoShape.values.firstWhere(
        (e) => e.name == profile.logoShape,
        orElse: () => LogoShape.square,
      );
      _logoFitMode = LogoFitMode.values.firstWhere(
        (e) => e.name == profile.logoFitMode,
        orElse: () => LogoFitMode.cover,
      );
      _logoZoom = profile.logoZoom;
      _logoOffsetX = profile.logoOffsetX;
      _logoOffsetY = profile.logoOffsetY;
      _logoPadding = profile.logoPadding;
      _logoBgEnabled = profile.logoBgEnabled;
      _logoBytes = (profile.logoBase64 == null || profile.logoBase64!.isEmpty)
          ? null
          : base64Decode(profile.logoBase64!);
      _activeStyleProfileId = profile.id;
    });
    _queueSavePrefs();
  }

  Future<void> _saveAsNewStyleProfile() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save Style Preset'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Preset name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    final trimmed = (name ?? '').trim();
    if (trimmed.isEmpty) return;

    final id = 'custom_${DateTime.now().millisecondsSinceEpoch}';
    final profile = _buildCurrentStyleProfile(id: id, name: trimmed);
    final profiles = await QrStyleService.createProfileFromLegacy(profile);
    if (!mounted) return;
    setState(() {
      _styleProfiles = profiles;
      _activeStyleProfileId = id;
    });
    _snack('Style preset saved.');
  }

  Future<void> _deleteStyleProfile(String profileId) async {
    final isProtected = profileId == 'default' || profileId == 'brand';
    if (isProtected) {
      _snack('This preset cannot be deleted.', isError: true);
      return;
    }
    final profileName = _styleProfiles
        .firstWhere(
          (p) => p.id == profileId,
          orElse: QrStyleProfile.defaultProfile,
        )
        .name;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.themeCard,
        title: Text(
          'Delete "$profileName"?',
          style: TextStyle(
            color: context.themeTextPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          'This preset will be permanently removed.',
          style: TextStyle(color: context.themeTextSecondary, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: TextStyle(color: context.themeTextSecondary),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: context.themeError),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    final profiles = await QrStyleService.deleteProfile(profileId);
    if (!mounted) return;
    setState(() {
      _styleProfiles = profiles;
      if (_activeStyleProfileId == profileId) {
        _activeStyleProfileId = profiles.first.id;
        _applyStyleProfile(profiles.first);
      }
    });
    _snack('Preset deleted.');
  }

  Future<void> _selectStyleProfile(String profileId) async {
    final profile = _styleProfiles.firstWhere(
      (p) => p.id == profileId,
      orElse: QrStyleProfile.defaultProfile,
    );
    await QrStyleService.setActiveProfile(profile.id);
    _applyStyleProfile(profile);
  }

  bool get _isColorChanged =>
      _fgColor != Colors.black ||
      _eyeColor != Colors.black ||
      _bgColor != Colors.white;

  bool get _isShapeChanged =>
      _eyeShape != QrEyeShape.square ||
      _moduleShape != QrDataModuleShape.square ||
      _frameEnabled != false ||
      _frameThickness != 2 ||
      _frameColor != Colors.black;

  bool get _isLogoChanged =>
      _logoBytes != null ||
      _logoSize != 36 ||
      _logoShape != LogoShape.square ||
      _logoFitMode != LogoFitMode.cover ||
      _logoZoom != 1.0 ||
      _logoOffsetX != 0.0 ||
      _logoOffsetY != 0.0 ||
      _logoPadding != 4 ||
      _logoBgEnabled != true;

  bool get _isAnyStyleChanged =>
      _isColorChanged || _isShapeChanged || _isLogoChanged;

  Future<void> _handleReset(
    String category,
    bool Function() isChanged,
    VoidCallback resetLogic,
  ) async {
    if (!isChanged()) {
      _snack('Nothing to reset in $category.');
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.themeCard,
        title: Text(
          'Reset $category?',
          style: TextStyle(
            color: context.themeTextPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          'Are you sure you want to revert all $category styles?',
          style: TextStyle(color: context.themeTextSecondary, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: TextStyle(color: context.themeTextSecondary),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      _updateStyle(resetLogic);
      _snack('$category reset to default.');
    }
  }

  void _resetColor() {
    _fgColor = Colors.black;
    _eyeColor = Colors.black;
    _bgColor = Colors.white;
  }

  void _resetShape() {
    _eyeShape = QrEyeShape.square;
    _moduleShape = QrDataModuleShape.square;
    _frameEnabled = false;
    _frameThickness = 2;
    _frameColor = Colors.black;
  }

  void _resetLogo() {
    _logoBytes = null;
    _logoSize = 36;
    _logoShape = LogoShape.square;
    _logoFitMode = LogoFitMode.cover;
    _logoZoom = 1.0;
    _logoOffsetX = 0.0;
    _logoOffsetY = 0.0;
    _logoPadding = 4;
    _logoBgEnabled = true;
  }

  void _resetAllStyles() {
    _resetColor();
    _resetShape();
    _resetLogo();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final profiles = await QrStyleService.getProfiles();
    final activeId = await QrStyleService.getActiveProfileId();
    final activeProfile = profiles.firstWhere(
      (p) => p.id == activeId,
      orElse: () => profiles.first,
    );
    if (!mounted) return;
    setState(() {
      _styleProfiles = profiles;
      _activeStyleProfileId = activeProfile.id;
      _fgColor = Color(activeProfile.foregroundArgb);
      _eyeColor = Color(activeProfile.eyeArgb);
      _bgColor = Color(activeProfile.backgroundArgb);
      _ecLevel = activeProfile.errorCorrectionLevel;
      _eyeShape = QrEyeShape.values.firstWhere(
        (e) => e.name == activeProfile.eyeShape,
        orElse: () => QrEyeShape.square,
      );
      _moduleShape = QrDataModuleShape.values.firstWhere(
        (e) => e.name == activeProfile.moduleShape,
        orElse: () => QrDataModuleShape.square,
      );
      _frameEnabled = activeProfile.frameEnabled;
      _frameThickness = activeProfile.frameThickness;
      _frameColor = Color(activeProfile.frameColorArgb);
      _logoSize = activeProfile.logoSize;
      _logoShape = LogoShape.values.firstWhere(
        (e) => e.name == activeProfile.logoShape,
        orElse: () => LogoShape.square,
      );
      _logoFitMode = LogoFitMode.values.firstWhere(
        (e) => e.name == activeProfile.logoFitMode,
        orElse: () => LogoFitMode.cover,
      );
      _logoZoom = activeProfile.logoZoom;
      _logoOffsetX = activeProfile.logoOffsetX;
      _logoOffsetY = activeProfile.logoOffsetY;
      _logoPadding = activeProfile.logoPadding;
      _logoBgEnabled = activeProfile.logoBgEnabled;
      _logoBytes =
          (activeProfile.logoBase64 == null ||
              activeProfile.logoBase64!.isEmpty)
          ? null
          : base64Decode(activeProfile.logoBase64!);
    });

    final path = prefs.getString('logoPath');
    if (_logoBytes == null && path != null && path.isNotEmpty) {
      final file = File(path);
      if (await file.exists()) {
        final b = await file.readAsBytes();
        if (mounted) setState(() => _logoBytes = b);
      }
    }
  }

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final activeName = _styleProfiles
        .firstWhere(
          (e) => e.id == _activeStyleProfileId,
          orElse: QrStyleProfile.defaultProfile,
        )
        .name;
    final profile = _buildCurrentStyleProfile(
      id: _activeStyleProfileId,
      name: activeName,
    );
    final profiles = await QrStyleService.upsertProfile(profile);
    await QrStyleService.setActiveProfile(_activeStyleProfileId);
    if (mounted) setState(() => _styleProfiles = profiles);

    if (_logoBytes != null) {
      final dir = await getApplicationDocumentsDirectory();
      final path = '${dir.path}/current_logo.png';
      await File(path).writeAsBytes(_logoBytes!);
      await prefs.setString('logoPath', path);
    } else {
      await prefs.remove('logoPath');
      final dir = await getApplicationDocumentsDirectory();
      final path = '${dir.path}/current_logo.png';
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
  }

  @override
  void dispose() {
    widget.cloneTextListenable?.removeListener(_onCloneTextRequested);
    _textController.dispose();
    super.dispose();
  }

  void _onCloneTextRequested() {
    final raw = widget.cloneTextListenable?.value;
    final value = raw?.trim() ?? '';
    if (value.isEmpty) return;

    setState(() {
      _dataType = DataType.text;
      _sectionTabIndex = 0;
      _encodedData = '';
    });
    _textController
      ..text = value
      ..selection = TextSelection.fromPosition(
        TextPosition(offset: value.length),
      );

    widget.cloneTextListenable?.value = null;
  }

  Future<void> _scanToClone() async {
    final scanned = await Navigator.of(
      context,
    ).push<String>(FadeSlideRoute(page: const ScanScreen.pickForClone()));
    if (!mounted) return;
    final value = (scanned ?? '').trim();
    if (value.isEmpty) return;

    setState(() {
      _dataType = DataType.text;
      _sectionTabIndex = 0;
      _encodedData = '';
    });
    _textController
      ..text = value
      ..selection = TextSelection.fromPosition(
        TextPosition(offset: value.length),
      );
    _snack('Scanned data added to Create.');
  }

  String get _displayData {
    if (_dataType == DataType.text) return _textController.text;
    return _encodedData;
  }

  String _displayDataForTextValue(TextEditingValue value) {
    if (_dataType == DataType.text) return value.text;
    return _encodedData;
  }

  Future<Uint8List?> _captureImage() async {
    await Future.delayed(const Duration(milliseconds: 80));
    try {
      final boundary =
          _previewKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveToGallery() async {
    if (_displayData.isEmpty) {
      _snack('Enter some data first.', isError: true);
      return;
    }
    setState(() => _isSaving = true);
    final bytes = await _captureImage();
    if (bytes == null) {
      if (mounted) setState(() => _isSaving = false);
      _snack('Could not render code.', isError: true);
      return;
    }
    try {
      final tempDir = await getTemporaryDirectory();
      final tempPath =
          '${tempDir.path}/qr_${DateTime.now().millisecondsSinceEpoch}.png';
      await File(tempPath).writeAsBytes(bytes);

      if (!await Gal.hasAccess()) await Gal.requestAccess();
      await Gal.putImage(tempPath);

      final docDir = await getApplicationDocumentsDirectory();
      final docPath =
          '${docDir.path}/history_${DateTime.now().millisecondsSinceEpoch}.png';
      await File(docPath).writeAsBytes(bytes);

      final thumbnail = await _buildHistoryThumbnail(bytes);
      await _saveHistory(thumbnailBytes: thumbnail, imagePath: docPath);

      if (!mounted) return;
      _snack('Saved to gallery.');
      ReviewService.triggerSuccessReview(context);
      AdManager.instance.showInterstitial(context);
    } catch (e) {
      if (mounted) _snack('Save failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _share() async {
    if (_displayData.isEmpty) {
      _snack('Enter some data first.', isError: true);
      return;
    }
    final bytes = await _captureImage();
    if (bytes == null) {
      if (mounted) _snack('Could not render code.', isError: true);
      return;
    }
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/qr_share_${DateTime.now().millisecondsSinceEpoch}.png';
    await File(path).writeAsBytes(bytes);

    final docDir = await getApplicationDocumentsDirectory();
    final docPath =
        '${docDir.path}/history_${DateTime.now().millisecondsSinceEpoch}.png';
    await File(docPath).writeAsBytes(bytes);

    final thumbnail = await _buildHistoryThumbnail(bytes);
    // Fixed: was missing await — history save was racing against share intent.
    await _saveHistory(thumbnailBytes: thumbnail, imagePath: docPath);

    if (!mounted) return;
    await SharePlus.instance.share(ShareParams(files: [XFile(path)]));
  }

  Future<void> _clearCurrentData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear data?'),
        content: const Text('This will clear all entered data.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    _textController.clear();
    _encodedDataCache.clear();
    setState(() => _encodedData = '');
  }

  Future<void> _openFullscreenPreview() async {
    final data = _displayData.trim();
    if (data.isEmpty) {
      _snack('Enter some data first.', isError: true);
      return;
    }

    // Snapshot current style params
    final fgColor = _fgColor;
    final eyeColor = _eyeColor;
    final bgColor = _bgColor;
    final ecLevel = _ecLevel;
    final logoBytes = _logoBytes;
    final logoSize = _logoSize;
    final logoShape = _logoShape;
    final logoFitMode = _logoFitMode;
    final logoZoom = _logoZoom;
    final logoOffsetX = _logoOffsetX;
    final logoOffsetY = _logoOffsetY;
    final logoPadding = _logoPadding;
    final logoBgEnabled = _logoBgEnabled;
    final eyeShape = _eyeShape;
    final moduleShape = _moduleShape;
    final frameEnabled = _frameEnabled;
    final frameThickness = _frameThickness;
    final frameColor = _frameColor;
    final genType = _genType;

    await Navigator.of(context).push(
      FadeSlideRoute(
        page: Builder(
          builder: (ctx) {
            final fullscreenPreviewKey = GlobalKey();
            bool isSaving = false;

            return StatefulBuilder(
              builder: (ctx, setRouteState) {
                Future<Uint8List?> captureRouteImage() async {
                  await Future.delayed(const Duration(milliseconds: 80));
                  try {
                    final boundary =
                        fullscreenPreviewKey.currentContext?.findRenderObject()
                            as RenderRepaintBoundary?;
                    if (boundary == null) return null;
                    final image = await boundary.toImage(pixelRatio: 3.0);
                    final byteData = await image.toByteData(
                      format: ui.ImageByteFormat.png,
                    );
                    return byteData?.buffer.asUint8List();
                  } catch (_) {
                    return null;
                  }
                }

                return Scaffold(
                  appBar: AppBar(
                    title: const Text('Preview'),
                    actions: [
                      IconButton(
                        icon: const Icon(Icons.share_rounded),
                        tooltip: 'Share',
                        onPressed: () async {
                          final bytes = await captureRouteImage();
                          if (bytes == null) return;
                          final dir = await getTemporaryDirectory();
                          final path =
                              '${dir.path}/qr_share_${DateTime.now().millisecondsSinceEpoch}.png';
                          await File(path).writeAsBytes(bytes);
                          if (!ctx.mounted) return;
                          await SharePlus.instance.share(
                            ShareParams(files: [XFile(path)]),
                          );
                        },
                      ),
                      IconButton(
                        icon: isSaving
                            ? const Icon(Icons.hourglass_top_rounded)
                            : const Icon(Icons.download_rounded),
                        tooltip: isSaving ? 'Saving…' : 'Save to gallery',
                        onPressed: isSaving
                            ? null
                            : () async {
                                setRouteState(() => isSaving = true);
                                try {
                                  final bytes = await captureRouteImage();
                                  if (bytes == null) return;
                                  final tempDir = await getTemporaryDirectory();
                                  final tempPath =
                                      '${tempDir.path}/qr_${DateTime.now().millisecondsSinceEpoch}.png';
                                  await File(tempPath).writeAsBytes(bytes);
                                  if (!await Gal.hasAccess()) {
                                    await Gal.requestAccess();
                                  }
                                  await Gal.putImage(tempPath);
                                  if (ctx.mounted) {
                                    ScaffoldMessenger.of(ctx).showSnackBar(
                                      SnackBar(
                                        content: const Text(
                                          'Saved to gallery.',
                                        ),
                                        backgroundColor: ctx.themeSuccess,
                                      ),
                                    );
                                  }
                                } finally {
                                  setRouteState(() => isSaving = false);
                                }
                              },
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  body: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: FittedBox(
                        fit: BoxFit.contain,
                        child: PreviewCard(
                          exportKey: fullscreenPreviewKey,
                          data: data,
                          type: genType,
                          foregroundColor: fgColor,
                          eyeColor: eyeColor,
                          backgroundColor: bgColor,
                          errorCorrectionLevel: ecLevel,
                          embeddedLogo: logoBytes == null
                              ? null
                              : MemoryImage(logoBytes),
                          logoSize: logoSize,
                          logoShape: logoShape,
                          logoFitMode: logoFitMode,
                          logoZoom: logoZoom,
                          logoOffsetX: logoOffsetX,
                          logoOffsetY: logoOffsetY,
                          logoPadding: logoPadding,
                          logoBgEnabled: logoBgEnabled,
                          eyeShape: eyeShape,
                          moduleShape: moduleShape,
                          frameEnabled: frameEnabled,
                          frameThickness: frameThickness,
                          frameColor: frameColor,
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Future<Uint8List?> _buildHistoryThumbnail(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: 96,
        targetHeight: 96,
      );
      final frame = await codec.getNextFrame();
      final thumbData = await frame.image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      return thumbData?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveHistory({
    Uint8List? thumbnailBytes,
    String? imagePath,
  }) async {
    final label = _displayData.length > 40
        ? '${_displayData.substring(0, 40)}...'
        : _displayData;
    await HistoryService.save(
      HistoryEntry(
        data: _displayData,
        dataType: _dataType.key,
        generatorType: _genType.name,
        createdAt: DateTime.now(),
        label: label,
        thumbnailBytes: thumbnailBytes,
        imagePath: imagePath,
      ),
    );
  }

  // Fixed: added mounted guard — _snack was called after async gaps
  // (e.g. in _share, _clearCurrentData) without checking if widget is
  // still mounted, which throws if the screen was popped.
  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? context.themeError : context.themeSuccess,
      ),
    );
  }

  Future<Color?> _showColorPickerDialog({
    required String title,
    required Color initial,
  }) async {
    Color temp = initial;
    final hexCtrl = TextEditingController(
      text: temp.toARGB32().toRadixString(16).substring(2).toUpperCase(),
    );
    return showDialog<Color>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: context.themeCard,
          title: Text(
            title,
            style: TextStyle(
              color: context.themeTextPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                BlockPicker(
                  pickerColor: temp,
                  availableColors: const [
                    Colors.red,
                    Colors.pink,
                    Colors.blueAccent,
                    Colors.lightBlueAccent,
                    Colors.cyanAccent,
                    Colors.blue,
                    Colors.lightBlue,
                    Colors.cyan,
                    Colors.teal,
                    Colors.green,
                    Colors.lightGreen,
                    Colors.lime,
                    Colors.yellow,
                    Colors.amber,
                    Colors.orange,
                    Colors.deepOrange,
                    Colors.brown,
                    Colors.grey,
                    Colors.blueGrey,
                    Colors.black,
                    Colors.white,
                  ],
                  itemBuilder: (color, isCurrentColor, changeColor) {
                    return GestureDetector(
                      onTap: changeColor,
                      child: Container(
                        margin: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: color == Colors.white
                              ? Border.all(color: Colors.black26, width: 2)
                              : null,
                          boxShadow: [
                            BoxShadow(
                              color: color.withValues(alpha: 0.8),
                              offset: const Offset(1, 2),
                              blurRadius: 3,
                            ),
                          ],
                        ),
                        child: isCurrentColor
                            ? Icon(
                                Icons.check,
                                color: useWhiteForeground(color)
                                    ? Colors.white
                                    : Colors.black,
                              )
                            : null,
                      ),
                    );
                  },
                  onColorChanged: (c) {
                    setState(() {
                      temp = c;
                      hexCtrl.text = c
                          .toARGB32()
                          .toRadixString(16)
                          .substring(2)
                          .toUpperCase();
                    });
                  },
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text(
                      'Hex: #',
                      style: TextStyle(
                        color: context.themeTextPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: hexCtrl,
                        style: TextStyle(
                          color: context.themeTextPrimary,
                          fontSize: 14,
                        ),
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 12,
                          ),
                          filled: true,
                          fillColor: context.themeSurface,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: context.themeBorder),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: context.themeBorder),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: context.themeAccent),
                          ),
                        ),
                        onChanged: (val) {
                          if (val.length == 6 || val.length == 8) {
                            final code = int.tryParse(val, radix: 16);
                            if (code != null) {
                              setState(() {
                                temp = Color(
                                  val.length == 6 ? code + 0xFF000000 : code,
                                );
                              });
                            }
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: temp,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: context.themeBorder,
                          width: 2,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                'Cancel',
                style: TextStyle(color: context.themeTextSecondary),
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, temp),
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
  }

  Future<Uint8List?> _pickLogoBytes() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: false,
      );
      if (result == null || result.files.isEmpty) return null;
      final originalPath = result.files.single.path;
      if (originalPath == null) return null;
      if (!mounted) return null;

      final croppedFile = await ImageCropper().cropImage(
        sourcePath: originalPath,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Crop Logo',
            toolbarColor: context.themeSurface,
            toolbarWidgetColor: context.themeTextPrimary,
            initAspectRatio: CropAspectRatioPreset.square,
            lockAspectRatio: false,
          ),
          IOSUiSettings(title: 'Crop Logo'),
        ],
      );

      if (croppedFile != null) {
        return await croppedFile.readAsBytes();
      }
      return null;
    } catch (e) {
      if (mounted) _snack('Could not load logo: $e', isError: true);
      return null;
    }
  }

  Widget _buildStyleTab() {
    final t = Theme.of(context);

    Widget sectionLabel(
      String text, {
      VoidCallback? onReset,
      bool showReset = false,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            text.toUpperCase(),
            style: t.textTheme.labelSmall?.copyWith(
              color: context.themeTextSecondary,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
            ),
          ),
          if (showReset)
            TextButton(
              onPressed: onReset,
              style: TextButton.styleFrom(
                minimumSize: const Size(48, 36),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                'RESET',
                style: t.textTheme.labelSmall?.copyWith(
                  color: context.themeAccent,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );

    Widget segmentedRow<T>({
      required List<({String label, IconData icon, T value})> options,
      required T selected,
      required ValueChanged<T> onChanged,
    }) {
      return Container(
        decoration: BoxDecoration(
          color: context.themeSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.themeBorder),
        ),
        padding: const EdgeInsets.all(4),
        child: Row(
          children: options.map((opt) {
            final isSelected = opt.value == selected;
            return Expanded(
              child: GestureDetector(
                onTap: () => onChanged(opt.value),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeInOut,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? context.themeAccent.withValues(alpha: 0.15)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        opt.icon,
                        size: 20,
                        color: isSelected
                            ? context.themeAccent
                            : context.themeTextSecondary,
                      ),
                      const SizedBox(height: 5),
                      Text(
                        opt.label,
                        textAlign: TextAlign.center,
                        style: t.textTheme.labelSmall?.copyWith(
                          color: isSelected
                              ? context.themeAccent
                              : context.themeTextSecondary,
                          fontWeight: isSelected
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      );
    }

    Widget presetSelector() {
      final activeProfile = _styleProfiles.firstWhere(
        (p) => p.id == _activeStyleProfileId,
        orElse: () => _styleProfiles.isNotEmpty
            ? _styleProfiles.first
            : QrStyleProfile.defaultProfile(),
      );
      final isProtected =
          activeProfile.id == 'default' || activeProfile.id == 'brand';

      return Column(
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _activeStyleProfileId,
                  dropdownColor: context.themeSurface,
                  icon: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: context.themeTextSecondary,
                    size: 20,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Style Preset',
                    labelStyle: t.textTheme.labelSmall?.copyWith(
                      color: context.themeTextSecondary,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    filled: true,
                    fillColor: context.themeSurface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: context.themeBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: context.themeBorder),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: context.themeAccent),
                    ),
                  ),
                  items: _styleProfiles.map((p) {
                    final isActive = p.id == _activeStyleProfileId;
                    return DropdownMenuItem<String>(
                      value: p.id,
                      child: Text(
                        p.name,
                        style: t.textTheme.bodyMedium?.copyWith(
                          color: isActive
                              ? context.themeAccent
                              : context.themeTextPrimary,
                          fontWeight: isActive
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) _selectStyleProfile(val);
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _saveAsNewStyleProfile,
                icon: const Icon(Icons.add_rounded, size: 20),
                tooltip: 'Save current as preset',
                style: IconButton.styleFrom(
                  backgroundColor: context.themeAccent.withValues(alpha: 0.1),
                  padding: const EdgeInsets.all(12),
                  foregroundColor: context.themeAccent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              if (!isProtected) ...[
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () => _deleteStyleProfile(_activeStyleProfileId),
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    color: context.themeError,
                    size: 20,
                  ),
                  tooltip: 'Delete preset',
                  style: IconButton.styleFrom(
                    backgroundColor: context.themeError.withValues(alpha: 0.1),
                    padding: const EdgeInsets.all(12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      );
    }

    return DefaultTabController(
      length: 3,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          presetSelector(),
          const SizedBox(height: 10),
          TabBar(
            isScrollable: false,
            labelColor: context.themeAccent,
            unselectedLabelColor: context.themeTextSecondary,
            indicatorColor: context.themeAccent,
            labelStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
            unselectedLabelStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
            tabs: const [
              Tab(text: 'Colors'),
              Tab(text: 'Shapes'),
              Tab(text: 'Logo'),
            ],
          ),
          const SizedBox(height: 10),
          Builder(
            builder: (ctx) {
              final tabCtrl = DefaultTabController.of(ctx);
              return AnimatedBuilder(
                animation: tabCtrl,
                builder: (context, _) {
                  return AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: [
                      // ── Tab 0: Colors ─────────────────────
                      Column(
                        key: const ValueKey(0),
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          sectionLabel(
                            'Colors',
                            showReset: _isColorChanged,
                            onReset: () => _handleReset(
                              'colors',
                              () => _isColorChanged,
                              _resetColor,
                            ),
                          ),
                          _ColorTile(
                            label: 'Module Color',
                            color: _fgColor,
                            onTap: () async {
                              final c = await _showColorPickerDialog(
                                title: 'Module Color',
                                initial: _fgColor,
                              );
                              if (c != null) {
                                _updateStyle(() => _fgColor = c);
                              }
                            },
                          ),
                          const SizedBox(height: 10),
                          _ColorTile(
                            label: 'Eye Color',
                            color: _eyeColor,
                            onTap: () async {
                              final c = await _showColorPickerDialog(
                                title: 'Eye Color',
                                initial: _eyeColor,
                              );
                              if (c != null) {
                                _updateStyle(() => _eyeColor = c);
                              }
                            },
                          ),
                          const SizedBox(height: 10),
                          _ColorTile(
                            label: 'Background',
                            color: _bgColor,
                            onTap: () async {
                              final c = await _showColorPickerDialog(
                                title: 'Background',
                                initial: _bgColor,
                              );
                              if (c != null) {
                                _updateStyle(() => _bgColor = c);
                              }
                            },
                          ),
                          const SizedBox(height: 10),
                          _ColorTile(
                            label: 'Frame Color',
                            color: _frameColor,
                            onTap: () async {
                              final c = await _showColorPickerDialog(
                                title: 'Frame Color',
                                initial: _frameColor,
                              );
                              if (c != null) {
                                _updateStyle(() => _frameColor = c);
                              }
                            },
                          ),
                        ],
                      ),

                      // ── Tab 1: Shapes ─────────────────────
                      Column(
                        key: const ValueKey(1),
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          sectionLabel(
                            'Shape & Output',
                            showReset: _isShapeChanged,
                            onReset: () => _handleReset(
                              'shapes',
                              () => _isShapeChanged,
                              _resetShape,
                            ),
                          ),
                          segmentedRow<QrEyeShape>(
                            options: [
                              (
                                label: 'Square',
                                icon: Icons.crop_square_rounded,
                                value: QrEyeShape.square,
                              ),
                              (
                                label: 'Rounded',
                                icon: Icons.rounded_corner_rounded,
                                value: QrEyeShape.circle,
                              ),
                            ],
                            selected: _eyeShape,
                            onChanged: (v) => _updateStyle(() => _eyeShape = v),
                          ),
                          sectionLabel('Data Modules'),
                          segmentedRow<QrDataModuleShape>(
                            options: [
                              (
                                label: 'Square',
                                icon: Icons.grid_on_rounded,
                                value: QrDataModuleShape.square,
                              ),
                              (
                                label: 'Rounded',
                                icon: Icons.blur_on_rounded,
                                value: QrDataModuleShape.circle,
                              ),
                            ],
                            selected: _moduleShape,
                            onChanged: (v) =>
                                _updateStyle(() => _moduleShape = v),
                          ),
                          sectionLabel('Error Correction'),
                          Container(
                            decoration: BoxDecoration(
                              color: context.themeSurface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: context.themeBorder),
                            ),
                            padding: const EdgeInsets.all(4),
                            child: Row(
                              children: _ecLevels.map((e) {
                                final isSelected = _ecLevel == e.value;
                                return Expanded(
                                  child: GestureDetector(
                                    onTap: () =>
                                        _updateStyle(() => _ecLevel = e.value),
                                    child: AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 180,
                                      ),
                                      curve: Curves.easeInOut,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 10,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? context.themeAccent.withValues(
                                                alpha: 0.15,
                                              )
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        e.label,
                                        textAlign: TextAlign.center,
                                        style: t.textTheme.labelMedium
                                            ?.copyWith(
                                              color: isSelected
                                                  ? context.themeAccent
                                                  : context.themeTextSecondary,
                                              fontWeight: isSelected
                                                  ? FontWeight.w700
                                                  : FontWeight.w500,
                                            ),
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                          sectionLabel('Frame'),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  'Enable QR frame',
                                  style: t.textTheme.bodySmall?.copyWith(
                                    color: context.themeTextSecondary,
                                  ),
                                ),
                              ),
                              Switch(
                                value: _frameEnabled,
                                onChanged: (v) =>
                                    _updateStyle(() => _frameEnabled = v),
                                activeThumbColor: context.themeAccent,
                              ),
                            ],
                          ),
                          if (_frameEnabled) ...[
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Thickness',
                                  style: t.textTheme.bodySmall?.copyWith(
                                    color: context.themeTextSecondary,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: context.themeAccent.withValues(
                                      alpha: 0.12,
                                    ),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '${_frameThickness.toStringAsFixed(1)} px',
                                    style: t.textTheme.labelSmall?.copyWith(
                                      color: context.themeAccent,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            Slider(
                              min: 1,
                              max: 10,
                              divisions: 18,
                              value: _frameThickness,
                              onChanged: (v) =>
                                  _updateStyle(() => _frameThickness = v),
                            ),
                          ],
                        ],
                      ),

                      // ── Tab 2: Logo ───────────────────────
                      Column(
                        key: const ValueKey(2),
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          sectionLabel(
                            'Logo & Crop',
                            showReset: _isLogoChanged,
                            onReset: () => _handleReset(
                              'logo',
                              () => _isLogoChanged,
                              _resetLogo,
                            ),
                          ),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () async {
                                    final b = await _pickLogoBytes();
                                    if (b != null) {
                                      _updateStyle(() {
                                        _logoBytes = b;
                                        _logoFitMode = LogoFitMode.cover;
                                        _logoZoom = 1.0;
                                        _logoOffsetX = 0.0;
                                        _logoOffsetY = 0.0;
                                      });
                                    }
                                  },
                                  icon: const Icon(
                                    Icons.image_outlined,
                                    size: 16,
                                  ),
                                  label: Text(
                                    _logoBytes == null
                                        ? 'Upload logo'
                                        : 'Change logo',
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                  ),
                                ),
                              ),
                              if (_logoBytes != null) ...[
                                const SizedBox(width: 8),
                                OutlinedButton.icon(
                                  onPressed: () => _updateStyle(() {
                                    _logoBytes = null;
                                  }),
                                  icon: const Icon(
                                    Icons.delete_outline_rounded,
                                    size: 16,
                                  ),
                                  label: const Text('Remove'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: context.themeError,
                                    side: BorderSide(
                                      color: context.themeError.withValues(
                                        alpha: 0.4,
                                      ),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          if (_logoBytes != null) ...[
                            const SizedBox(height: 16),
                            sectionLabel('Size'),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Logo size',
                                  style: t.textTheme.bodySmall?.copyWith(
                                    color: context.themeTextSecondary,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: context.themeAccent.withValues(
                                      alpha: 0.12,
                                    ),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '${_logoSize.toInt()} px',
                                    style: t.textTheme.labelSmall?.copyWith(
                                      color: context.themeAccent,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            Slider(
                              min: 16,
                              max: 80,
                              value: _logoSize,
                              onChanged: (v) =>
                                  _updateStyle(() => _logoSize = v),
                            ),
                            sectionLabel('Shape'),
                            segmentedRow<LogoShape>(
                              options: LogoShape.values
                                  .map(
                                    (s) => (
                                      label: s.label,
                                      icon: s.icon,
                                      value: s,
                                    ),
                                  )
                                  .toList(),
                              selected: _logoShape,
                              onChanged: (v) =>
                                  _updateStyle(() => _logoShape = v),
                            ),
                            sectionLabel('Fitting'),
                            segmentedRow<LogoFitMode>(
                              options: LogoFitMode.values
                                  .map(
                                    (m) => (
                                      label: m.label,
                                      icon: m.icon,
                                      value: m,
                                    ),
                                  )
                                  .toList(),
                              selected: _logoFitMode,
                              onChanged: (v) =>
                                  _updateStyle(() => _logoFitMode = v),
                            ),
                            sectionLabel('Crop & Position'),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Zoom',
                                  style: t.textTheme.bodySmall?.copyWith(
                                    color: context.themeTextSecondary,
                                  ),
                                ),
                                Text(
                                  '${_logoZoom.toStringAsFixed(2)}x',
                                  style: t.textTheme.labelSmall?.copyWith(
                                    color: context.themeAccent,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                            Slider(
                              min: 1.0,
                              max: 3.0,
                              divisions: 20,
                              value: _logoZoom,
                              onChanged: (v) =>
                                  _updateStyle(() => _logoZoom = v),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Horizontal',
                                  style: t.textTheme.bodySmall?.copyWith(
                                    color: context.themeTextSecondary,
                                  ),
                                ),
                                Text(
                                  _logoOffsetX.toStringAsFixed(2),
                                  style: t.textTheme.labelSmall?.copyWith(
                                    color: context.themeAccent,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                            Slider(
                              min: -1.0,
                              max: 1.0,
                              divisions: 20,
                              value: _logoOffsetX,
                              onChanged: (v) =>
                                  _updateStyle(() => _logoOffsetX = v),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Vertical',
                                  style: t.textTheme.bodySmall?.copyWith(
                                    color: context.themeTextSecondary,
                                  ),
                                ),
                                Text(
                                  _logoOffsetY.toStringAsFixed(2),
                                  style: t.textTheme.labelSmall?.copyWith(
                                    color: context.themeAccent,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                            Slider(
                              min: -1.0,
                              max: 1.0,
                              divisions: 20,
                              value: _logoOffsetY,
                              onChanged: (v) =>
                                  _updateStyle(() => _logoOffsetY = v),
                            ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                onPressed: () => _updateStyle(() {
                                  _logoZoom = 1.0;
                                  _logoOffsetX = 0.0;
                                  _logoOffsetY = 0.0;
                                }),
                                icon: const Icon(
                                  Icons.restart_alt_rounded,
                                  size: 16,
                                ),
                                label: const Text('Reset crop'),
                              ),
                            ),
                            sectionLabel('Background'),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'White background',
                                        style: t.textTheme.bodySmall?.copyWith(
                                          color: context.themeTextSecondary,
                                        ),
                                      ),
                                      Text(
                                        'Improves scannability',
                                        style: t.textTheme.bodySmall?.copyWith(
                                          fontSize: 11,
                                          color: context.themeTextSecondary
                                              .withValues(alpha: 0.6),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Switch(
                                  value: _logoBgEnabled,
                                  onChanged: (v) =>
                                      _updateStyle(() => _logoBgEnabled = v),
                                  activeThumbColor: context.themeAccent,
                                ),
                              ],
                            ),
                            sectionLabel('Padding'),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Padding',
                                  style: t.textTheme.bodySmall?.copyWith(
                                    color: context.themeTextSecondary,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: context.themeAccent.withValues(
                                      alpha: 0.12,
                                    ),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '${_logoPadding.toInt()} px',
                                    style: t.textTheme.labelSmall?.copyWith(
                                      color: context.themeAccent,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            Slider(
                              min: 0,
                              max: 16,
                              divisions: 16,
                              value: _logoPadding,
                              onChanged: (v) =>
                                  _updateStyle(() => _logoPadding = v),
                            ),
                          ],
                        ],
                      ),
                    ][tabCtrl.index],
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final keyboardInset = MediaQuery.of(context).viewInsets.bottom;
    final tabBottomPadding = keyboardInset + 16;
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusScope.of(context).unfocus(),
        child: Column(
          children: [
            // ── Pinned live preview ─────────────────────────────────
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _textController,
              builder: (_, value, _) {
                if (keyboardInset > 0) return const SizedBox.shrink();
                final data = _displayDataForTextValue(value);
                final hasData = data.trim().isNotEmpty;
                return Container(
                  color: context.themeSurface,
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
                  child: AppCard(
                    borderRadius: 18,
                    padding: const EdgeInsets.fromLTRB(10, 8, 0, 6),
                    child: Column(
                      children: [
                        data.trim().isEmpty
                            ? SizedBox(
                                height: 80,
                                child: Center(
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        _genType == GeneratorType.qrCode
                                            ? Icons.qr_code_2_rounded
                                            : Icons.view_column_rounded,
                                        size: 30,
                                        color: context.themeTextSecondary
                                            .withValues(alpha: 0.25),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Your ${_genType.displayName} will appear here',
                                        style: t.textTheme.bodySmall?.copyWith(
                                          color: context.themeTextSecondary
                                              .withValues(alpha: 0.45),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            : SizedBox(
                                height: 140,
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    Center(
                                      child: FittedBox(
                                        fit: BoxFit.contain,
                                        child: PreviewCard(
                                          exportKey: _previewKey,
                                          data: data,
                                          type: _genType,
                                          foregroundColor: _fgColor,
                                          eyeColor: _eyeColor,
                                          backgroundColor: _bgColor,
                                          errorCorrectionLevel: _ecLevel,
                                          embeddedLogo: _logoBytes == null
                                              ? null
                                              : MemoryImage(_logoBytes!),
                                          logoSize: _logoSize,
                                          logoShape: _logoShape,
                                          logoFitMode: _logoFitMode,
                                          logoZoom: _logoZoom,
                                          logoOffsetX: _logoOffsetX,
                                          logoOffsetY: _logoOffsetY,
                                          logoPadding: _logoPadding,
                                          logoBgEnabled: _logoBgEnabled,
                                          eyeShape: _eyeShape,
                                          moduleShape: _moduleShape,
                                          frameEnabled: _frameEnabled,
                                          frameThickness: _frameThickness,
                                          frameColor: _frameColor,
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      right: 0,
                                      top: 0,
                                      bottom: 0,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: context.themeAccent.withValues(
                                            alpha: 0.06,
                                          ),
                                          borderRadius: const BorderRadius.only(
                                            topLeft: Radius.circular(14),
                                            bottomLeft: Radius.circular(14),
                                          ),
                                          border: Border(
                                            left: BorderSide(
                                              color: context.themeAccent
                                                  .withValues(alpha: 0.15),
                                            ),
                                          ),
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 0,
                                        ),
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            _PreviewActionChip(
                                              icon: Icons.share_rounded,
                                              tooltip: 'Share',
                                              onPressed: hasData
                                                  ? _share
                                                  : null,
                                            ),
                                            const SizedBox(height: 4),
                                            _PreviewActionChip(
                                              icon: _isSaving
                                                  ? Icons.hourglass_top_rounded
                                                  : Icons.download_rounded,
                                              tooltip: _isSaving
                                                  ? 'Saving'
                                                  : 'Save',
                                              onPressed: hasData && !_isSaving
                                                  ? _saveToGallery
                                                  : null,
                                            ),
                                            Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 5,
                                                  ),
                                              child: SizedBox(
                                                width: 18,
                                                child: Divider(
                                                  height: 1,
                                                  thickness: 0.5,
                                                  color: context.themeAccent
                                                      .withValues(alpha: 0.2),
                                                ),
                                              ),
                                            ),
                                            _PreviewActionChip(
                                              icon: Icons.fullscreen_rounded,
                                              tooltip: 'Fullscreen',
                                              onPressed: hasData
                                                  ? _openFullscreenPreview
                                                  : null,
                                            ),
                                            const SizedBox(height: 4),
                                            _PreviewActionChip(
                                              icon: Icons.clear_rounded,
                                              tooltip: 'Clear',
                                              onPressed: hasData
                                                  ? _clearCurrentData
                                                  : null,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                      ],
                    ),
                  ),
                );
              },
            ),
            // ── Scrollable settings ─────────────────────────────────
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: DefaultTabController(
                  length: 3,
                  initialIndex: _sectionTabIndex,
                  child: Column(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: context.themeSurface,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: TabBar(
                          onTap: (index) =>
                              setState(() => _sectionTabIndex = index),
                          tabs: const [
                            Tab(text: 'Data'),
                            Tab(text: 'Format'),
                            Tab(text: 'Style'),
                          ],
                          labelColor: context.themeAccent,
                          unselectedLabelColor: context.themeTextSecondary,
                          indicatorColor: context.themeAccent,
                          dividerColor: Colors.transparent,
                          labelStyle: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                          unselectedLabelStyle: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 180),
                          child: _sectionTabIndex == 0
                              ? ListView(
                                  key: const ValueKey('encoding_tab'),
                                  keyboardDismissBehavior:
                                      ScrollViewKeyboardDismissBehavior.onDrag,
                                  padding: EdgeInsets.only(
                                    bottom: tabBottomPadding,
                                  ),
                                  children: [
                                    ValueListenableBuilder<TextEditingValue>(
                                      valueListenable: _textController,
                                      builder: (_, value, _) {
                                        final hasAnyData =
                                            value.text.isNotEmpty ||
                                            (_dataType != DataType.text &&
                                                _encodedData.isNotEmpty);
                                        return _SectionHeader(
                                          icon: Icons.data_object_rounded,
                                          title: 'What are you encoding?',
                                          trailing: hasAnyData
                                              ? GestureDetector(
                                                  onTap: _clearCurrentData,
                                                  child: Text(
                                                    'CLEAR',
                                                    style: t
                                                        .textTheme
                                                        .labelSmall
                                                        ?.copyWith(
                                                          color: context
                                                              .themeAccent,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                          fontSize: 10,
                                                        ),
                                                  ),
                                                )
                                              : null,
                                        );
                                      },
                                    ),
                                    const SizedBox(height: 10),
                                    TypeTabRow(
                                      selected: _dataType,
                                      onChanged: (d) {
                                        if (_dataType != DataType.text) {
                                          _encodedDataCache[_dataType] =
                                              _encodedData;
                                        }
                                        setState(() {
                                          _dataType = d;
                                          _encodedData =
                                              _encodedDataCache[d] ?? '';
                                        });
                                      },
                                    ),
                                    const SizedBox(height: 14),
                                    AppCard(
                                      padding: const EdgeInsets.all(16),
                                      child: AnimatedSwitcher(
                                        duration: const Duration(
                                          milliseconds: 200,
                                        ),
                                        child: KeyedSubtree(
                                          key: ValueKey(_dataType),
                                          child: _buildForm(),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    ValueListenableBuilder<TextEditingValue>(
                                      valueListenable: _textController,
                                      builder: (_, value, _) {
                                        if (_dataType != DataType.text) {
                                          return const SizedBox.shrink();
                                        }
                                        final len = value.text.length;
                                        final isWarning = len > 300;
                                        return Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 2,
                                          ),
                                          child: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.end,
                                            children: [
                                              if (isWarning)
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        right: 4,
                                                      ),
                                                  child: Icon(
                                                    Icons.warning_amber_rounded,
                                                    size: 13,
                                                    color: context.themeError,
                                                  ),
                                                ),
                                              Text(
                                                '$len / 500 chars',
                                                style: t.textTheme.labelSmall
                                                    ?.copyWith(
                                                      color: isWarning
                                                          ? context.themeError
                                                          : context
                                                                .themeTextSecondary,
                                                      fontWeight: isWarning
                                                          ? FontWeight.w600
                                                          : FontWeight.normal,
                                                    ),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                )
                              : _sectionTabIndex == 1
                              ? ListView(
                                  key: const ValueKey('format_tab'),
                                  keyboardDismissBehavior:
                                      ScrollViewKeyboardDismissBehavior.onDrag,
                                  padding: EdgeInsets.only(
                                    bottom: tabBottomPadding,
                                  ),
                                  children: [
                                    _SectionHeader(
                                      icon: Icons.grid_view_rounded,
                                      title: 'Output format',
                                    ),
                                    const SizedBox(height: 10),
                                    AppCard(
                                      padding: const EdgeInsets.all(14),
                                      child: FormatDropdown(
                                        selectedType: _genType,
                                        onChanged: (v) =>
                                            setState(() => _genType = v),
                                      ),
                                    ),
                                  ],
                                )
                              : ListView(
                                  key: const ValueKey('style_tab'),
                                  keyboardDismissBehavior:
                                      ScrollViewKeyboardDismissBehavior.onDrag,
                                  padding: EdgeInsets.only(
                                    bottom: tabBottomPadding,
                                  ),
                                  children: [
                                    _SectionHeader(
                                      icon: Icons.palette_rounded,
                                      title: 'Style & appearance',
                                      trailing: _isAnyStyleChanged
                                          ? TextButton(
                                              onPressed: () => _handleReset(
                                                'all styles',
                                                () => _isAnyStyleChanged,
                                                _resetAllStyles,
                                              ),
                                              style: TextButton.styleFrom(
                                                minimumSize: const Size(48, 36),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                    ),
                                                tapTargetSize:
                                                    MaterialTapTargetSize
                                                        .shrinkWrap,
                                              ),
                                              child: Text(
                                                'RESET ALL',
                                                style: t.textTheme.labelSmall
                                                    ?.copyWith(
                                                      color:
                                                          context.themeAccent,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                              ),
                                            )
                                          : null,
                                    ),
                                    const SizedBox(height: 10),
                                    if (_genType == GeneratorType.qrCode) ...[
                                      AppCard(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 8,
                                        ),
                                        child: AnimatedSwitcher(
                                          duration: const Duration(
                                            milliseconds: 200,
                                          ),
                                          switchInCurve: Curves.easeOut,
                                          switchOutCurve: Curves.easeOut,
                                          layoutBuilder:
                                              (
                                                currentChild,
                                                previousChildren,
                                              ) => Stack(
                                                alignment: Alignment.topCenter,
                                                children: [
                                                  ...previousChildren,
                                                  ?currentChild,
                                                ],
                                              ),
                                          child: _buildStyleTab(),
                                        ),
                                      ),
                                    ] else
                                      AppCard(
                                        padding: const EdgeInsets.all(14),
                                        child: Text(
                                          'Style customization is available for QR Code output.',
                                          style: t.textTheme.bodySmall
                                              ?.copyWith(
                                                color:
                                                    context.themeTextSecondary,
                                              ),
                                        ),
                                      ),
                                  ],
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            ValueListenableBuilder<bool>(
              valueListenable: AdManager.instance.isProNotifier,
              builder: (_, _, _) => AdManager.instance.getBannerAdWidget(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForm() {
    switch (_dataType) {
      case DataType.text:
        return TextForm(controller: _textController, onScanTap: _scanToClone);
      case DataType.wifi:
        return WifiForm(onChanged: (s) => setState(() => _encodedData = s));
      case DataType.vcard:
        return VCardForm(onChanged: (s) => setState(() => _encodedData = s));
      case DataType.email:
        return EmailForm(onChanged: (s) => setState(() => _encodedData = s));
    }
  }
}

class _ColorTile extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ColorTile({
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: context.themeSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.themeBorder),
        ),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: context.themeBorder, width: 1.5),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: context.themeTextPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    'Tap to change',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: context.themeTextSecondary,
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
  }
}

class _PreviewActionChip extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  const _PreviewActionChip({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Tooltip(
      message: tooltip,
      preferBelow: false,
      child: GestureDetector(
        onTap: onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: enabled
                ? context.themeAccent.withValues(alpha: 0.15)
                : context.themeSurface,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: Icon(
              icon,
              size: 15,
              color: enabled
                  ? context.themeAccent
                  : context.themeTextSecondary.withValues(alpha: 0.3),
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget? trailing;

  const _SectionHeader({
    required this.icon,
    required this.title,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: context.themeAccent),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: context.themeTextSecondary,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
            ),
          ),
        ),
        ?trailing,
      ],
    );
  }
}
