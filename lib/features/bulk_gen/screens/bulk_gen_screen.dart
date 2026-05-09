import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:printing/printing.dart';
import 'package:archive/archive_io.dart';
import '../../../core/ads/ad_manager.dart';
import '../../../core/style/qr_style_profile.dart';
import '../../../core/style/qr_style_service.dart';
import '../../../core/utils/review_service.dart';
import '../../../core/theme/app_card.dart';
import '../../../core/theme/app_theme.dart';
import '../../single_gen/models/generator_type.dart';
import '../../single_gen/widgets/format_dropdown.dart';
import '../services/file_parser.dart';
import '../services/pdf_grid_maker.dart';
import '../services/export_service.dart';

enum IngestionType { file, paste, sequence, scan }

class BulkGenScreen extends StatefulWidget {
  final bool isActive;
  const BulkGenScreen({super.key, this.isActive = true});

  @override
  State<BulkGenScreen> createState() => _BulkGenScreenState();
}

class _BulkGenScreenState extends State<BulkGenScreen> {
  GeneratorType _selectedType = GeneratorType.qrCode;
  bool _isLoading = false;
  static String? _lastGeneratedPdfPath;

  String _paperSize = 'A4';
  bool _includeLabels = true;
  _GridPreset _selectedGrid = const _GridPreset(rows: 4, cols: 3);

  IngestionType _ingestionType = IngestionType.file;
  bool _skipDuplicates = false;
  List<QrStyleProfile> _styleProfiles = const [];
  String _activeStyleProfileId = 'default';

  String _fileName = '';
  List<List<dynamic>> _rawFileData = [];
  List<String> _headers = [];
  bool _hasHeaders = true;
  int _colLabelIndex = 0;
  int _colDataIndex = 1;
  Set<int> _selectedRowIndices = {};

  final _pasteController = TextEditingController();
  final _seqPrefixController = TextEditingController();
  final _seqStartController = TextEditingController(text: '1');
  final _seqEndController = TextEditingController(text: '50');
  final _seqPadController = TextEditingController(text: '3');

  final MobileScannerController _scanController = MobileScannerController(
    autoStart: false,
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
    formats: [BarcodeFormat.all],
  );
  final List<String> _scannedItems = [];
  bool _scanRunning = false;
  bool _isProcessingScan = false;
  DateTime? _lastScanAt;
  String? _lastScanValue;

  bool _isCustomGrid = false;
  int _customRows = 6;
  int _customCols = 4;

  static const List<_GridPreset> _gridPresets = [
    _GridPreset(rows: 2, cols: 2),
    _GridPreset(rows: 3, cols: 2),
    _GridPreset(rows: 3, cols: 3),
    _GridPreset(rows: 4, cols: 3),
    _GridPreset(rows: 5, cols: 3),
  ];

  @override
  void initState() {
    super.initState();
    _loadStyleProfiles();
  }

  @override
  void didUpdateWidget(covariant BulkGenScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive == widget.isActive) return;
    if (!widget.isActive) {
      _scanController.stop();
      if (mounted) setState(() => _scanRunning = false);
    } else if (_ingestionType == IngestionType.scan) {
      _scanController.start();
      if (mounted) setState(() => _scanRunning = true);
      _loadStyleProfiles();
    } else if (widget.isActive) {
      _loadStyleProfiles();
    }
  }

  @override
  void dispose() {
    _scanController.dispose();
    _pasteController.dispose();
    _seqPrefixController.dispose();
    _seqStartController.dispose();
    _seqEndController.dispose();
    _seqPadController.dispose();
    super.dispose();
  }

  Future<void> _loadStyleProfiles() async {
    final profiles = await QrStyleService.getProfiles();
    final activeId = await QrStyleService.getActiveProfileId();
    if (!mounted) return;
    setState(() {
      _styleProfiles = profiles;
      _activeStyleProfileId = profiles.any((p) => p.id == activeId)
          ? activeId
          : profiles.first.id;
    });
  }

  Future<QrStyleProfile> _getLatestActiveStyleProfile() async {
    final profiles = await QrStyleService.getProfiles();
    final activeId = await QrStyleService.getActiveProfileId();
    final resolvedId = profiles.any((p) => p.id == activeId)
        ? activeId
        : profiles.first.id;
    final profile = profiles.firstWhere((p) => p.id == resolvedId);
    if (mounted) {
      setState(() {
        _styleProfiles = profiles;
        _activeStyleProfileId = resolvedId;
      });
    } else {
      _styleProfiles = profiles;
      _activeStyleProfileId = resolvedId;
    }
    return profile;
  }

  // ── live item count ────────────────────────────────────────────────────
  int get _liveItemCount {
    switch (_ingestionType) {
      case IngestionType.file:
        return _selectedRowIndices.length;
      case IngestionType.scan:
        return _scannedItems.length;
      case IngestionType.paste:
        return _pasteController.text
            .split('\n')
            .where((l) => l.trim().isNotEmpty)
            .length;
      case IngestionType.sequence:
        final start = int.tryParse(_seqStartController.text) ?? 1;
        final end = int.tryParse(_seqEndController.text) ?? 50;
        return (end - start).abs() + 1;
    }
  }

  // ── Import File ───────────────────────────────────────────────────────
  Future<void> _importFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'txt', 'xlsx', 'xls'],
    );
    if (result == null || result.files.single.path == null) return;

    setState(() => _isLoading = true);
    try {
      final parsed = await FileParser.parseFile(result.files.single);
      if (parsed.isEmpty) {
        throw Exception('File is empty or unrecognized format.');
      }

      late final List<String> headers;
      if (_hasHeaders && parsed.isNotEmpty) {
        headers = parsed.first.map((e) => e.toString().trim()).toList();
        parsed.removeAt(0);
      } else {
        final columnCount = parsed.first.length;
        headers = List.generate(columnCount, (i) => 'Column ${i + 1}');
      }

      setState(() {
        _rawFileData = parsed;
        _headers = headers.isNotEmpty ? headers : ['Col A', 'Col B'];
        _fileName = result.files.single.name;
        _colLabelIndex = 0;
        _colDataIndex = _headers.length > 1 ? 1 : 0;
        for (int i = 0; i < _headers.length; i++) {
          final h = _headers[i].toLowerCase();
          if (h.contains('label') || h.contains('title') || h.contains('name')) {
            _colLabelIndex = i;
          }
          if (h.contains('data') ||
              h.contains('url') ||
              h.contains('link') ||
              h.contains('code')) {
            _colDataIndex = i;
          }
        }
        _selectedRowIndices = Set.from(Iterable.generate(_rawFileData.length));
      });
    } catch (e) {
      if (mounted) _snack('Could not read file: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _downloadTemplate() async {
    const template = _templateCsv;
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/bulk_qr_template.csv';
    await File(path).writeAsString(template);
    await SharePlus.instance.share(
      ShareParams(files: [XFile(path)], text: 'ScanSheet Template'),
    );
  }

  static const String _templateCsv =
      'Label,Data\nProduct A,https://example.com/a\nProduct B,SKU-1234\n';

  Future<void> _saveTemplateToUserPath() async {
    try {
      final selectedPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save CSV Template',
        fileName: 'bulk_qr_template.csv',
        type: FileType.custom,
        allowedExtensions: const ['csv'],
      );
      if (selectedPath == null || selectedPath.trim().isEmpty) return;
      var finalPath = selectedPath;
      if (!finalPath.toLowerCase().endsWith('.csv')) {
        finalPath = '$finalPath.csv';
      }
      await File(finalPath).writeAsString(_templateCsv);
      if (mounted) _snack('Template saved to: $finalPath');
    } catch (e) {
      if (mounted) _snack('Could not save template: $e', isError: true);
    }
  }

  Future<void> _openTemplateDialog() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: context.themeCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: context.themeAccentContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.table_chart_rounded,
                        size: 18,
                        color: context.themeAccent,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'CSV Template',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: context.themeTextPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: Icon(
                        Icons.close_rounded,
                        color: context.themeTextSecondary,
                      ),
                      tooltip: 'Close',
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: context.themeBorder),
                    color: context.themeSurface,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        headingRowHeight: 42,
                        dataRowMinHeight: 42,
                        dataRowMaxHeight: 48,
                        horizontalMargin: 14,
                        columnSpacing: 20,
                        headingRowColor: WidgetStatePropertyAll(
                          context.themeAccentContainer.withValues(alpha: 0.45),
                        ),
                        columns: [
                          DataColumn(
                            label: Text(
                              'Label',
                              style: TextStyle(
                                color: context.themeTextPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          DataColumn(
                            label: Text(
                              'Data',
                              style: TextStyle(
                                color: context.themeTextPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                        rows: [
                          DataRow(
                            cells: [
                              const DataCell(Text('Product A')),
                              DataCell(
                                Text(
                                  'https://example.com/a',
                                  style: TextStyle(color: context.themeAccent),
                                ),
                              ),
                            ],
                          ),
                          const DataRow(
                            cells: [
                              DataCell(Text('Product B')),
                              DataCell(Text('SKU-1234')),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          Navigator.pop(ctx);
                          await _downloadTemplate();
                        },
                        icon: const Icon(Icons.share_rounded, size: 16),
                        label: const Text('Share'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () async {
                          Navigator.pop(ctx);
                          await _saveTemplateToUserPath();
                        },
                        icon: const Icon(Icons.download_rounded, size: 16),
                        label: const Text('Save'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Data Construction ────────────────────────────────────────────────────
  List<List<dynamic>> _buildFinalData() {
    List<List<dynamic>> list = [];

    if (_ingestionType == IngestionType.file) {
      for (int i = 0; i < _rawFileData.length; i++) {
        if (!_selectedRowIndices.contains(i)) continue;
        final row = _rawFileData[i];
        final label = _colLabelIndex < row.length
            ? row[_colLabelIndex].toString()
            : '';
        final data = _colDataIndex < row.length
            ? row[_colDataIndex].toString()
            : label;
        list.add([label, data]);
      }
    } else if (_ingestionType == IngestionType.paste) {
      for (var line in _pasteController.text.split('\n')) {
        final val = line.trim();
        if (val.isNotEmpty) list.add([val, val]);
      }
    } else if (_ingestionType == IngestionType.sequence) {
      int start = int.tryParse(_seqStartController.text) ?? 1;
      int end = int.tryParse(_seqEndController.text) ?? 50;
      int pad = int.tryParse(_seqPadController.text) ?? 0;
      String prefix = _seqPrefixController.text;
      if (start > end) {
        int t = start;
        start = end;
        end = t;
      }
      for (int i = start; i <= end; i++) {
        final val = '$prefix${i.toString().padLeft(pad, '0')}';
        list.add([val, val]);
      }
    } else if (_ingestionType == IngestionType.scan) {
      for (final item in _scannedItems) {
        final val = item.trim();
        if (val.isNotEmpty) list.add([val, val]);
      }
    }

    if (_skipDuplicates) {
      final Set<String> seen = {};
      final List<List<dynamic>> deduped = [];
      for (var row in list) {
        final key = '${row[0]}_|_${row[1]}';
        if (seen.add(key)) deduped.add(row);
      }
      list = deduped;
    }
    return list;
  }

  Future<Uint8List?> _renderStyledQrBytes(
    String data,
    QrStyleProfile style,
  ) async {
    try {
      final eyeShape = style.eyeShape == 'circle'
          ? QrEyeShape.circle
          : QrEyeShape.square;
      final moduleShape = style.moduleShape == 'circle'
          ? QrDataModuleShape.circle
          : QrDataModuleShape.square;
      final painter = QrPainter(
        data: data,
        version: QrVersions.auto,
        errorCorrectionLevel: style.errorCorrectionLevel,
        eyeStyle: QrEyeStyle(eyeShape: eyeShape, color: Color(style.eyeArgb)),
        dataModuleStyle: QrDataModuleStyle(
          dataModuleShape: moduleShape,
          color: Color(style.foregroundArgb),
        ),
      );
      final qrImage = await painter.toImage(1024);
      final logoBytes = (style.logoBase64 == null || style.logoBase64!.isEmpty)
          ? null
          : base64Decode(style.logoBase64!);
      final logoImage = logoBytes == null
          ? null
          : await _decodeUiImage(logoBytes);
      if (logoBytes != null && logoImage == null) return null;
      return await _composeQrWithLogo(
        qrImage: qrImage,
        logoImage: logoImage,
        style: style,
      );
    } catch (_) {
      return null;
    }
  }

  Future<ui.Image?> _decodeUiImage(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      return frame.image;
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List?> _composeQrWithLogo({
    required ui.Image qrImage,
    required ui.Image? logoImage,
    required QrStyleProfile style,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const double canvasSize = 1024;
    final qrRect = Rect.fromLTWH(0, 0, canvasSize, canvasSize);
    canvas.drawRect(qrRect, Paint()..color = Color(style.backgroundArgb));
    paintImage(
      canvas: canvas,
      rect: qrRect,
      image: qrImage,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
    );

    if (logoImage != null) {
      final logoBox = style.logoSize.clamp(12, 120) / 250.0 * canvasSize;
      final totalBox =
          (style.logoSize + (style.logoBgEnabled ? style.logoPadding * 2 : 0))
              .clamp(12, 140) /
          250.0 *
          canvasSize;
      final center = Offset(canvasSize / 2, canvasSize / 2);
      final bgRect = Rect.fromCenter(
        center: center,
        width: totalBox,
        height: totalBox,
      );
      final logoRect = Rect.fromCenter(
        center: center,
        width: logoBox,
        height: logoBox,
      );
      RRect shapeRRect;
      switch (style.logoShape) {
        case 'circle':
          shapeRRect = RRect.fromRectAndRadius(
            bgRect,
            Radius.circular(totalBox),
          );
          break;
        case 'rounded':
          shapeRRect = RRect.fromRectAndRadius(
            bgRect,
            Radius.circular(totalBox * 0.22),
          );
          break;
        default:
          shapeRRect = RRect.fromRectAndRadius(
            bgRect,
            const Radius.circular(2),
          );
      }
      if (style.logoBgEnabled) {
        canvas.drawRRect(shapeRRect, Paint()..color = const Color(0xFFFFFFFF));
      }
      final fit = switch (style.logoFitMode) {
        'contain' => BoxFit.contain,
        'fill' => BoxFit.fill,
        _ => BoxFit.cover,
      };
      final fitted = applyBoxFit(
        fit,
        Size(
          logoImage.width.toDouble() / style.logoZoom.clamp(1.0, 3.0),
          logoImage.height.toDouble() / style.logoZoom.clamp(1.0, 3.0),
        ),
        Size(logoBox, logoBox),
      );
      final srcCenter = Offset(
        logoImage.width / 2 +
            ((logoImage.width - fitted.source.width) / 2) * style.logoOffsetX,
        logoImage.height / 2 +
            ((logoImage.height - fitted.source.height) / 2) * style.logoOffsetY,
      );
      final src = Rect.fromCenter(
        center: srcCenter,
        width: fitted.source.width.clamp(1, logoImage.width.toDouble()),
        height: fitted.source.height.clamp(1, logoImage.height.toDouble()),
      );
      final dst = Alignment.center.inscribe(fitted.destination, logoRect);
      canvas.save();
      if (style.logoShape == 'circle') {
        canvas.clipPath(Path()..addOval(logoRect));
      } else if (style.logoShape == 'rounded') {
        canvas.clipRRect(
          RRect.fromRectAndRadius(logoRect, Radius.circular(logoBox * 0.18)),
        );
      } else {
        canvas.clipRect(logoRect);
      }
      canvas.drawImageRect(logoImage, src, dst, Paint());
      canvas.restore();
    }

    final image = await recorder.endRecording().toImage(
      canvasSize.toInt(),
      canvasSize.toInt(),
    );
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  }

  Future<({List<List<dynamic>> rows, int failedCount})> _buildFinalDataForPdf(
    List<List<dynamic>> baseData,
    QrStyleProfile style,
  ) async {
    if (_selectedType != GeneratorType.qrCode) {
      return (rows: baseData, failedCount: 0);
    }
    final List<List<dynamic>> styled = [];
    int failedCount = 0;
    for (final row in baseData) {
      final label = row[0].toString();
      final payload = row[1].toString();
      final qrBytes = await _renderStyledQrBytes(payload, style);
      if (qrBytes == null) {
        failedCount++;
        styled.add([label, payload]);
      } else {
        styled.add([label, payload, qrBytes]);
      }
    }
    return (rows: styled, failedCount: failedCount);
  }

  // ── PDF Export ───────────────────────────────────────────────────────────
  void _previewPdfFirstPage() async {
    final finalData = _buildFinalData();
    if (finalData.isEmpty) {
      _snack('No valid data available to preview.', isError: true);
      return;
    }
    if (!_validateGridLayout()) return;
    _showSimpleLoading('Generating preview\u2026');
    try {
      final int itemsPerPage = _selectedGrid.rows * _selectedGrid.cols;
      final previewData = finalData.take(itemsPerPage).toList();
      final style = await _getLatestActiveStyleProfile();
      final pdfBuild = await _buildFinalDataForPdf(previewData, style);
      final bytes = await PdfGridMaker.generateGridPdf(
        data: pdfBuild.rows,
        type: _selectedType,
        paperSize: _paperSize,
        includeLabels: _includeLabels,
        rows: _selectedGrid.rows,
        cols: _selectedGrid.cols,
        codeColorArgb: style.foregroundArgb,
        codeBackgroundArgb: style.backgroundArgb,
        labelColorArgb: style.foregroundArgb,
        cardBorderColorArgb: style.eyeArgb,
        qrFrameEnabled: style.frameEnabled,
        qrFrameThickness: style.frameThickness,
        qrFrameColorArgb: style.frameColorArgb,
      );
      Uint8List? imageBytes;
      await for (var page in Printing.raster(bytes, pages: [0], dpi: 150)) {
        imageBytes = await page.toPng();
        break;
      }
      if (!mounted) return;
      Navigator.pop(context);
      if (pdfBuild.failedCount > 0) {
        _snack(
          'Style could not be applied on ${pdfBuild.failedCount} item(s).',
          isError: true,
        );
      }
      if (imageBytes != null) {
        showDialog(
          context: context,
          builder: (_) => Dialog(
            backgroundColor: context.themeCard,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Preview (Page 1)',
                        style: TextStyle(
                          color: context.themeTextPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.close_rounded,
                          color: context.themeTextSecondary,
                          size: 22,
                        ),
                        onPressed: () => Navigator.pop(context),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(
                        Icons.pinch_rounded,
                        size: 14,
                        color: context.themeTextSecondary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Pinch to zoom',
                        style: TextStyle(
                          fontSize: 12,
                          color: context.themeTextSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: Container(
                      decoration: BoxDecoration(
                        color: context.themeSurface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: context.themeBorder),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(11),
                        child: SizedBox(
                          width: double.maxFinite,
                          child: InteractiveViewer(
                            panEnabled: true,
                            minScale: 1.0,
                            maxScale: 4.0,
                            child: Image.memory(
                              imageBytes!,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      } else {
        _snack('Unable to generate preview image.', isError: true);
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        _snack('Preview Error: $e', isError: true);
      }
    }
  }

  void _generatePdf() async {
    final finalData = _buildFinalData();
    if (finalData.isEmpty) {
      _snack('No valid data available to generate PDF.', isError: true);
      return;
    }
    if (!AdManager.instance.isPro && _liveItemCount > 10) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Free version is limited to 10 items per batch.'),
          ),
        );
        AdManager.onShowPaywall?.call(context);
      }
      return;
    }
    if (finalData.length > 1000) {
      _showTooBigDialog();
      return;
    }
    if (!_validateGridLayout()) return;

    await ExportService.processExport<Uint8List>(
      context: context,
      loadingMessage: 'Generating ${finalData.length} items\u2026',
      fileExtension: 'pdf',
      shareText: 'Your QR label sheet',
      generator: () async {
        final style = await _getLatestActiveStyleProfile();
        final pdfBuild = await _buildFinalDataForPdf(finalData, style);
        if (pdfBuild.failedCount > 0 && mounted) {
          _snack(
            'Style could not be applied on ${pdfBuild.failedCount} item(s).',
            isError: true,
          );
        }
        return await PdfGridMaker.generateGridPdf(
          data: pdfBuild.rows,
          type: _selectedType,
          paperSize: _paperSize,
          includeLabels: _includeLabels,
          rows: _selectedGrid.rows,
          cols: _selectedGrid.cols,
          codeColorArgb: style.foregroundArgb,
          codeBackgroundArgb: style.backgroundArgb,
          labelColorArgb: style.foregroundArgb,
          cardBorderColorArgb: style.eyeArgb,
          qrFrameEnabled: style.frameEnabled,
          qrFrameThickness: style.frameThickness,
          qrFrameColorArgb: style.frameColorArgb,
        );
      },
      onGetFileData: (bytes) async {
        final dir = await getApplicationDocumentsDirectory();
        final path =
            '${dir.path}/BatchStudio_${DateTime.now().millisecondsSinceEpoch}.pdf';
        await File(path).writeAsBytes(bytes);
        _lastGeneratedPdfPath = path;
        if (mounted) ReviewService.triggerSuccessReview(context);
        return (path, bytes);
      },
    );
  }

  // ── ZIP Export ───────────────────────────────────────────────────────────
  void _exportZip() async {
    final finalData = _buildFinalData();
    if (finalData.isEmpty) {
      _snack('No valid data to export.', isError: true);
      return;
    }
    if (!AdManager.instance.isPro && _liveItemCount > 10) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Free version is limited to 10 items per batch.'),
          ),
        );
        AdManager.onShowPaywall?.call(context);
      }
      return;
    }
    if (finalData.length > 1000) {
      _showTooBigDialog();
      return;
    }

    await ExportService.processExport<Uint8List>(
      context: context,
      loadingMessage: 'Rendering ${finalData.length} QR images\u2026',
      fileExtension: 'zip',
      shareText: 'Your QR images',
      generator: () async {
        final style = await _getLatestActiveStyleProfile();
        final archive = Archive();
        int failedCount = 0;
        final Map<String, int> nameCount = {};

        for (final row in finalData) {
          final label = row[0].toString();
          final payload = row[1].toString();
          Uint8List? pngBytes;
          if (_selectedType == GeneratorType.qrCode) {
            pngBytes = await _renderStyledQrBytes(payload, style);
          }
          if (pngBytes == null) {
            failedCount++;
            continue;
          }
          final safeBase = label
              .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
              .replaceAll(RegExp(r'\s+'), '_')
              .substring(0, label.length.clamp(0, 60));
          final baseName = safeBase.isEmpty ? 'qr' : safeBase;
          final count = nameCount[baseName] ?? 0;
          nameCount[baseName] = count + 1;
          final fileName = count == 0
              ? '$baseName.png'
              : '${baseName}_$count.png';
          archive.addFile(ArchiveFile(fileName, pngBytes.length, pngBytes));
        }

        if (archive.isEmpty) throw Exception('No QR images could be rendered.');
        if (failedCount > 0 && mounted) {
          _snack(
            '$failedCount item(s) skipped (could not render).',
            isError: true,
          );
        }

        final encodedBytes = ZipEncoder().encode(archive);
        if (encodedBytes == null) throw Exception('Failed to encode ZIP.');
        return Uint8List.fromList(encodedBytes);
      },
      onGetFileData: (bytes) async {
        final dir = await getApplicationDocumentsDirectory();
        final path =
            '${dir.path}/ScanSheet_${DateTime.now().millisecondsSinceEpoch}.zip';
        await File(path).writeAsBytes(bytes);
        if (mounted) ReviewService.triggerSuccessReview(context);
        return (path, bytes);
      },
    );
  }

  void _showSimpleLoading(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: context.themeCard,
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(
              strokeWidth: 2,
              color: context.themeAccent,
            ),
            const SizedBox(width: 20),
            Text(
              message,
              style: TextStyle(color: context.themeTextPrimary, fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }

  void _showTooBigDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: context.themeCard,
        title: Text(
          'Batch Too Large',
          style: TextStyle(
            color: context.themeTextPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          'Please split your batches into 1,000 items at a time.',
          style: TextStyle(color: context.themeTextSecondary, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _snack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? context.themeError : context.themeSuccess,
      ),
    );
  }

  bool _validateGridLayout() {
    final isA4 = _paperSize == 'A4';
    final paperWidth = isA4 ? 595.0 : 612.0;
    final paperHeight = isA4 ? 842.0 : 792.0;
    final availWidth = paperWidth - 40;
    final availHeight = paperHeight - 40;
    final cols = _selectedGrid.cols;
    final rows = _selectedGrid.rows;
    if (cols <= 0 || rows <= 0) return false;
    final itemWidth = (availWidth - (cols - 1) * 20) / cols;
    final totalHeightNeeded = (rows * itemWidth) + ((rows - 1) * 20);
    if (totalHeightNeeded > availHeight) {
      _snack(
        'The selected layout ($rows rows \u00d7 $cols columns) is too large to fit on a single $_paperSize page.',
        isError: true,
      );
      return false;
    }
    return true;
  }

  Widget _buildNumberAdjuster({
    required String label,
    required int value,
    required int min,
    required int max,
    required ValueChanged<int> onChanged,
  }) {
    final t = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4.0, bottom: 6.0),
          child: Text(
            label,
            style: t.textTheme.labelSmall?.copyWith(
              color: context.themeTextSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: context.themeSurface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: context.themeBorder),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.remove, size: 20),
                color: context.themeTextPrimary,
                onPressed: value > min ? () => onChanged(value - 1) : null,
              ),
              Text(
                value.toString(),
                style: t.textTheme.titleMedium?.copyWith(
                  color: context.themeTextPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add, size: 20),
                color: context.themeTextPrimary,
                onPressed: value < max ? () => onChanged(value + 1) : null,
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── UI ───────────────────────────────────────────────────────────────────
  Widget _buildFileView() {
    final t = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _isLoading ? null : _importFile,
            icon: _isLoading
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: context.themeAccent,
                    ),
                  )
                : const Icon(Icons.upload_file_outlined, size: 18),
            label: Text(_isLoading ? 'Importing\u2026' : 'Select CSV or XLSX'),
            style: OutlinedButton.styleFrom(
              foregroundColor: context.themeAccent,
              side: BorderSide(color: context.themeAccent),
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                'File contains headers',
                style: t.textTheme.bodySmall?.copyWith(
                  color: context.themeTextSecondary,
                ),
              ),
            ),
            Switch(
              value: _hasHeaders,
              onChanged: (v) => setState(() => _hasHeaders = v),
              activeThumbColor: context.themeAccent,
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _openTemplateDialog,
            icon: const Icon(Icons.download_outlined, size: 17),
            label: const Text('Get CSV Template'),
            style: OutlinedButton.styleFrom(
              foregroundColor: context.themeTextSecondary,
              side: BorderSide(color: context.themeBorder),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
        if (_rawFileData.isNotEmpty) ...[
          const SizedBox(height: 14),
          Row(
            children: [
              Icon(
                Icons.check_circle_outline_rounded,
                size: 15,
                color: context.themeSuccess,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  '$_fileName  \u00b7  ${_rawFileData.length} rows detected',
                  style: t.textTheme.bodySmall?.copyWith(
                    color: context.themeSuccess,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(),
          const SizedBox(height: 10),
          Text(
            'Column Mapping',
            style: t.textTheme.labelSmall?.copyWith(
              color: context.themeTextSecondary,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildDropdown(
                  'Label Text',
                  _colLabelIndex,
                  (v) => setState(() => _colLabelIndex = v ?? 0),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildDropdown(
                  'QR Data',
                  _colDataIndex,
                  (v) => setState(() => _colDataIndex = v ?? 0),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Row Selection',
                style: t.textTheme.labelSmall?.copyWith(
                  color: context.themeTextSecondary,
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Row(
                children: [
                  TextButton(
                    onPressed: () => setState(
                      () => _selectedRowIndices = Set.from(
                        Iterable.generate(_rawFileData.length),
                      ),
                    ),
                    child: Text(
                      'All',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.themeAccent,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () =>
                        setState(() => _selectedRowIndices.clear()),
                    child: Text(
                      'None',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.themeTextSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          Container(
            height: 180,
            decoration: BoxDecoration(
              border: Border.all(color: context.themeBorder),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ListView.builder(
              itemCount: _rawFileData.length,
              itemBuilder: (ctx, i) {
                final row = _rawFileData[i];
                final isSelected = _selectedRowIndices.contains(i);
                final labelText = _colLabelIndex < row.length
                    ? row[_colLabelIndex].toString()
                    : '';
                return CheckboxListTile(
                  value: isSelected,
                  dense: true,
                  activeColor: context.themeAccent,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(
                    labelText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  ),
                  onChanged: (v) => setState(() {
                    if (v == true) {
                      _selectedRowIndices.add(i);
                    } else {
                      _selectedRowIndices.remove(i);
                    }
                  }),
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildDropdown(String label, int value, ValueChanged<int?> onChanged) {
    final t = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: t.textTheme.bodySmall?.copyWith(
            color: context.themeTextSecondary,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: context.themeSurface,
            border: Border.all(color: context.themeBorder),
            borderRadius: BorderRadius.circular(8),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              isExpanded: true,
              value: value,
              dropdownColor: context.themeSurface,
              style: TextStyle(color: context.themeTextPrimary, fontSize: 13),
              items: _headers
                  .asMap()
                  .entries
                  .map(
                    (e) => DropdownMenuItem<int>(
                      value: e.key,
                      child: Text(
                        e.value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPasteView() {
    final t = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Enter one item per line. The text will be used for both the printed label and the QR data.',
          style: t.textTheme.bodySmall?.copyWith(
            color: context.themeTextSecondary,
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _pasteController,
          maxLines: 10,
          style: const TextStyle(fontSize: 14),
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText:
                'https://example.com/item1\nhttps://example.com/item2\n...',
            suffixIcon: ValueListenableBuilder<TextEditingValue>(
              valueListenable: _pasteController,
              builder: (_, value, _) => value.text.isEmpty
                  ? const SizedBox.shrink()
                  : IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 16),
                      onPressed: () {
                        _pasteController.clear();
                        setState(() {});
                      },
                      tooltip: 'Clear',
                    ),
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
        ),
      ],
    );
  }

  Widget _buildSequenceView() {
    final t = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Instantly generate sequential codes (e.g., BIN-001, BIN-002...).',
          style: t.textTheme.bodySmall?.copyWith(
            color: context.themeTextSecondary,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              flex: 2,
              child: _buildInput('Prefix', _seqPrefixController, hint: 'BIN-'),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildInput(
                'Start',
                _seqStartController,
                isNumber: true,
                onChanged: () => setState(() {}),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildInput(
                'End',
                _seqEndController,
                isNumber: true,
                onChanged: () => setState(() {}),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildInput(
                'Pad',
                _seqPadController,
                isNumber: true,
                hint: '3',
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _setIngestionType(IngestionType type) async {
    if (_ingestionType == type) return;
    final previous = _ingestionType;
    setState(() => _ingestionType = type);
    if (previous == IngestionType.scan && type != IngestionType.scan) {
      try {
        await _scanController.stop();
        if (mounted) setState(() => _scanRunning = false);
      } catch (_) {}
    }
    if (previous != IngestionType.scan && type == IngestionType.scan) {
      try {
        await _scanController.start();
        if (mounted) setState(() => _scanRunning = true);
      } catch (_) {
        if (mounted) {
          _snack(
            'Could not start scanner. Please check camera permission.',
            isError: true,
          );
        }
      }
    }
  }

  Future<void> _toggleBatchScanner() async {
    try {
      if (_scanRunning) {
        await _scanController.stop();
      } else {
        await _scanController.start();
      }
      if (mounted) setState(() => _scanRunning = !_scanRunning);
    } catch (_) {
      if (mounted) _snack('Scanner control failed.', isError: true);
    }
  }

  Future<void> _onBatchScanDetect(BarcodeCapture capture) async {
    if (_isProcessingScan) return;
    final raw = capture.barcodes
        .map((b) => b.rawValue?.trim() ?? '')
        .firstWhere((v) => v.isNotEmpty, orElse: () => '');
    if (raw.isEmpty) return;
    final now = DateTime.now();
    if (_lastScanValue == raw &&
        _lastScanAt != null &&
        now.difference(_lastScanAt!) < const Duration(milliseconds: 1200)) {
      return;
    }
    _isProcessingScan = true;
    _lastScanAt = now;
    _lastScanValue = raw;
    try {
      await _scanController.stop();
      if (mounted) setState(() => _scanRunning = false);
      if (!mounted) return;
      setState(() => _scannedItems.add(raw));
    } finally {
      await Future.delayed(const Duration(milliseconds: 250));
      if (mounted && _ingestionType == IngestionType.scan) {
        try {
          await _scanController.start();
          if (mounted) setState(() => _scanRunning = true);
        } catch (_) {}
      }
      _isProcessingScan = false;
    }
  }

  Widget _buildScanView() {
    final t = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Scan products one-by-one to build a printable batch list instantly.',
          style: t.textTheme.bodySmall?.copyWith(
            color: context.themeTextSecondary,
          ),
        ),
        const SizedBox(height: 10),
        AppCard(
          padding: EdgeInsets.zero,
          borderRadius: 14,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: AspectRatio(
              aspectRatio: 16 / 10,
              child: MobileScanner(
                controller: _scanController,
                onDetect: _onBatchScanDetect,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Text(
                '${_scannedItems.length} item${_scannedItems.length == 1 ? '' : 's'} scanned',
                style: t.textTheme.bodySmall?.copyWith(
                  color: context.themeTextSecondary,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: _toggleBatchScanner,
              icon: Icon(
                _scanRunning ? Icons.pause_rounded : Icons.play_arrow_rounded,
                size: 16,
              ),
              label: Text(_scanRunning ? 'Pause' : 'Resume'),
            ),
            TextButton(
              onPressed: _scannedItems.isEmpty
                  ? null
                  : () => setState(() => _scannedItems.clear()),
              child: const Text('Clear List'),
            ),
          ],
        ),
        if (_scannedItems.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            height: 170,
            decoration: BoxDecoration(
              border: Border.all(color: context.themeBorder),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ListView.separated(
              itemCount: _scannedItems.length,
              separatorBuilder: (_, _) =>
                  Divider(height: 1, color: context.themeBorder),
              itemBuilder: (_, index) {
                final value = _scannedItems[index];
                return ListTile(
                  dense: true,
                  title: Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: () =>
                        setState(() => _scannedItems.removeAt(index)),
                    tooltip: 'Remove',
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildIngestionSelector() {
    final options = <({IngestionType type, String label, IconData icon})>[
      (
        type: IngestionType.file,
        label: 'File',
        icon: Icons.upload_file_rounded,
      ),
      (
        type: IngestionType.paste,
        label: 'Paste',
        icon: Icons.content_paste_rounded,
      ),
      (
        type: IngestionType.sequence,
        label: 'Sequence',
        icon: Icons.format_list_numbered_rounded,
      ),
      (
        type: IngestionType.scan,
        label: 'Scan',
        icon: Icons.qr_code_scanner_rounded,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = (constraints.maxWidth - 8) / 2;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: options.map((option) {
            final selected = _ingestionType == option.type;
            return SizedBox(
              width: itemWidth,
              child: InkWell(
                onTap: () => _setIngestionType(option.type),
                borderRadius: BorderRadius.circular(10),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 11,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? context.themeAccentContainer
                        : context.themeSurface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: selected
                          ? context.themeAccent
                          : context.themeBorder,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        option.icon,
                        size: 17,
                        color: selected
                            ? context.themeAccent
                            : context.themeTextSecondary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          option.label,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: selected
                                ? context.themeAccent
                                : context.themeTextPrimary,
                          ),
                        ),
                      ),
                      if (selected)
                        Icon(
                          Icons.check_circle_rounded,
                          size: 16,
                          color: context.themeAccent,
                        ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildStylePresetSelector() {
    final t = Theme.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _styleProfiles.map((option) {
        final selected = option.id == _activeStyleProfileId;
        return ChoiceChip(
          label: Text(option.name),
          selected: selected,
          onSelected: (_) async {
            await QrStyleService.setActiveProfile(option.id);
            if (!mounted) return;
            setState(() => _activeStyleProfileId = option.id);
          },
          selectedColor: context.themeAccentContainer,
          backgroundColor: context.themeSurface,
          side: BorderSide(
            color: selected ? context.themeAccent : context.themeBorder,
          ),
          labelStyle: t.textTheme.bodySmall?.copyWith(
            color: selected ? context.themeAccent : context.themeTextSecondary,
            fontWeight: FontWeight.w600,
          ),
        );
      }).toList(),
    );
  }

  Widget _buildInput(
    String label,
    TextEditingController controller, {
    bool isNumber = false,
    String? hint,
    VoidCallback? onChanged,
  }) {
    final t = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: t.textTheme.bodySmall?.copyWith(
            color: context.themeTextSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          keyboardType: isNumber ? TextInputType.number : TextInputType.text,
          style: const TextStyle(fontSize: 14),
          onChanged: onChanged != null ? (_) => onChanged() : null,
          decoration: InputDecoration(
            hintText: hint,
            suffixIcon: ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (_, value, _) => value.text.isEmpty
                  ? const SizedBox.shrink()
                  : IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 16),
                      onPressed: () {
                        controller.clear();
                        onChanged?.call();
                      },
                      tooltip: 'Clear',
                    ),
            ),
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
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final hasData = switch (_ingestionType) {
      IngestionType.file => _rawFileData.isNotEmpty,
      IngestionType.scan => _scannedItems.isNotEmpty,
      IngestionType.paste || IngestionType.sequence => true,
    };
    final itemCount = _liveItemCount;

    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => FocusScope.of(context).unfocus(),
              child: ListView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                children: [
                  _StepHeader(step: 1, label: 'Export Format', isActive: true),
                  const SizedBox(height: 10),
                  AppCard(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FormatDropdown(
                          selectedType: _selectedType,
                          onChanged: (v) => setState(() => _selectedType = v),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Text(
                              'Batch Style',
                              style: t.textTheme.bodySmall?.copyWith(
                                color: context.themeTextSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const Spacer(),
                            TextButton(
                              onPressed: _loadStyleProfiles,
                              child: const Text('Refresh'),
                            ),
                          ],
                        ),
                        _buildStylePresetSelector(),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  _StepHeader(
                    step: 2,
                    label: 'Data Source',
                    isActive: true,
                    badge: itemCount > 0 ? '$itemCount items' : null,
                  ),
                  const SizedBox(height: 10),
                  AppCard(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildIngestionSelector(),
                        const SizedBox(height: 16),
                        if (_ingestionType == IngestionType.file)
                          _buildFileView()
                        else if (_ingestionType == IngestionType.paste)
                          _buildPasteView()
                        else if (_ingestionType == IngestionType.sequence)
                          _buildSequenceView()
                        else
                          _buildScanView(),
                        const SizedBox(height: 16),
                        const Divider(),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Skip Duplicates',
                                    style: t.textTheme.bodyMedium?.copyWith(
                                      color: context.themeTextPrimary,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  Text(
                                    'Automatically remove duplicated rows or items.',
                                    style: t.textTheme.bodySmall?.copyWith(
                                      color: context.themeTextSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: _skipDuplicates,
                              onChanged: (v) =>
                                  setState(() => _skipDuplicates = v),
                              activeThumbColor: context.themeAccent,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  if (hasData) ...[
                    const SizedBox(height: 24),
                    _StepHeader(
                      step: 3,
                      label: 'PDF Layout',
                      isActive: true,
                      badge: itemCount > 0 ? '$itemCount items' : null,
                    ),
                    const SizedBox(height: 10),
                    AppCard(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Paper size',
                            style: t.textTheme.bodySmall?.copyWith(
                              color: context.themeTextSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 10),
                          SegmentedButton<String>(
                            segments: const [
                              ButtonSegment(value: 'A4', label: Text('A4')),
                              ButtonSegment(
                                value: 'US Letter',
                                label: Text('US Letter'),
                              ),
                            ],
                            selected: {_paperSize},
                            onSelectionChanged: (s) =>
                                setState(() => _paperSize = s.first),
                            style: SegmentedButton.styleFrom(
                              backgroundColor: context.themeSurface,
                              selectedBackgroundColor:
                                  context.themeAccentContainer,
                              selectedForegroundColor: context.themeAccent,
                              foregroundColor: context.themeTextSecondary,
                              side: BorderSide(color: context.themeBorder),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'Codes per page',
                            style: t.textTheme.bodySmall?.copyWith(
                              color: context.themeTextSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 10),
                          GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _gridPresets.length + 1,
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 3,
                                  crossAxisSpacing: 8,
                                  mainAxisSpacing: 8,
                                  childAspectRatio: 1.9,
                                ),
                            itemBuilder: (_, index) {
                              if (index == _gridPresets.length) {
                                final selected = _isCustomGrid;
                                return InkWell(
                                  onTap: () => setState(() {
                                    _isCustomGrid = true;
                                    _selectedGrid = _GridPreset(
                                      rows: _customRows,
                                      cols: _customCols,
                                    );
                                  }),
                                  borderRadius: BorderRadius.circular(10),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: selected
                                          ? context.themeAccentContainer
                                          : context.themeSurface,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: selected
                                            ? context.themeAccent
                                            : context.themeBorder,
                                        width: selected ? 1.2 : 1,
                                      ),
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      'Custom',
                                      style: t.textTheme.labelMedium?.copyWith(
                                        color: selected
                                            ? context.themeAccent
                                            : context.themeTextSecondary,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                );
                              }
                              final preset = _gridPresets[index];
                              final selected =
                                  !_isCustomGrid && preset == _selectedGrid;
                              return InkWell(
                                onTap: () => setState(() {
                                  _isCustomGrid = false;
                                  _selectedGrid = preset;
                                }),
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: selected
                                        ? context.themeAccentContainer
                                        : context.themeSurface,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: selected
                                          ? context.themeAccent
                                          : context.themeBorder,
                                      width: selected ? 1.2 : 1,
                                    ),
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    preset.display,
                                    style: t.textTheme.labelMedium?.copyWith(
                                      color: selected
                                          ? context.themeAccent
                                          : context.themeTextSecondary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                          if (_isCustomGrid) ...[
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: _buildNumberAdjuster(
                                    label: 'Rows',
                                    value: _customRows,
                                    min: 1,
                                    max: 20,
                                    onChanged: (v) => setState(() {
                                      _customRows = v;
                                      _selectedGrid = _GridPreset(
                                        rows: _customRows,
                                        cols: _customCols,
                                      );
                                    }),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: _buildNumberAdjuster(
                                    label: 'Columns',
                                    value: _customCols,
                                    min: 1,
                                    max: 10,
                                    onChanged: (v) => setState(() {
                                      _customCols = v;
                                      _selectedGrid = _GridPreset(
                                        rows: _customRows,
                                        cols: _customCols,
                                      );
                                    }),
                                  ),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 14),
                          const Divider(),
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Include label text',
                                      style: t.textTheme.bodyMedium?.copyWith(
                                        color: context.themeTextPrimary,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    Text(
                                      'Print the label name under each code',
                                      style: t.textTheme.bodySmall?.copyWith(
                                        color: context.themeTextSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Switch(
                                value: _includeLabels,
                                onChanged: (v) =>
                                    setState(() => _includeLabels = v),
                                activeThumbColor: context.themeAccent,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _previewPdfFirstPage,
                        icon: const Icon(Icons.preview_rounded, size: 18),
                        label: const Text('Preview First Page'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: context.themeAccent,
                          side: BorderSide(color: context.themeAccent),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _generatePdf,
                            icon: const Icon(
                              Icons.picture_as_pdf_rounded,
                              size: 18,
                            ),
                            label: const Text('Export PDF'),
                            style: FilledButton.styleFrom(
                              backgroundColor: context.themeAccent,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 15),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _exportZip,
                            icon: const Icon(
                              Icons.folder_zip_rounded,
                              size: 18,
                            ),
                            label: const Text('Export ZIP'),
                            style: FilledButton.styleFrom(
                              backgroundColor: context.themeAccent.withValues(
                                alpha: 0.15,
                              ),
                              foregroundColor: context.themeAccent,
                              padding: const EdgeInsets.symmetric(vertical: 15),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 0,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_lastGeneratedPdfPath != null &&
                        File(_lastGeneratedPdfPath!).existsSync()) ...[
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            await SharePlus.instance.share(
                              ShareParams(
                                files: [XFile(_lastGeneratedPdfPath!)],
                                text: 'Your QR label sheet',
                              ),
                            );
                          },
                          icon: const Icon(Icons.share_rounded, size: 17),
                          label: const Text('Re-share last PDF'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: context.themeAccent,
                            side: BorderSide(color: context.themeAccent),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                    if (!AdManager.instance.isPro) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Free: up to 10 items. Upgrade for up to 1,000 per batch.',
                        textAlign: TextAlign.center,
                        style: t.textTheme.bodySmall?.copyWith(
                          color: context.themeTextSecondary,
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
          AdManager.instance.getBannerAdWidget(),
        ],
      ),
    );
  }
}

class _StepHeader extends StatelessWidget {
  final int step;
  final String label;
  final bool isActive;
  final String? badge;
  const _StepHeader({
    required this.step,
    required this.label,
    this.isActive = false,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: isActive
                ? context.themeAccent.withValues(alpha: 0.15)
                : context.themeSurface,
            shape: BoxShape.circle,
            border: Border.all(
              color: isActive ? context.themeAccent : context.themeBorder,
              width: 1.5,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            '$step',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: isActive
                  ? context.themeAccent
                  : context.themeTextSecondary,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          label.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: context.themeTextSecondary,
            letterSpacing: 1.1,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (badge != null) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: context.themeAccentContainer,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              badge!,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: context.themeAccent,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _GridPreset {
  final int rows;
  final int cols;
  const _GridPreset({required this.rows, required this.cols});
  String get display => '${rows}x$cols';
  @override
  bool operator ==(Object other) =>
      other is _GridPreset && other.rows == rows && other.cols == cols;
  @override
  int get hashCode => Object.hash(rows, cols);
}
