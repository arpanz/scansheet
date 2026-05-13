import 'dart:convert';
import 'dart:io';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/services/export_service.dart';
import '../../../core/services/google_sheets_service.dart';
import '../../../core/services/scan_session_service.dart';
import '../../../core/services/template_service.dart';
import '../../../core/theme/app_card.dart';
import '../../../core/theme/app_theme.dart';
import '../models/scan_session.dart';

/// Full-page Export & Templates screen.
/// Phase 6 — format picker + template gallery + live table preview + export.
class ExportTemplatesScreen extends StatefulWidget {
  final ScanSession session;

  const ExportTemplatesScreen({super.key, required this.session});

  @override
  State<ExportTemplatesScreen> createState() => _ExportTemplatesScreenState();
}

enum _ExportFormat { csv, excel, googleSheets }

class _ExportTemplatesScreenState extends State<ExportTemplatesScreen> {
  late List<SessionRow> _rows;
  _ExportFormat _selectedFormat = _ExportFormat.csv;
  SessionTemplate? _selectedTemplate;
  bool _isExporting = false;

  // All templates (built-in + user)
  late List<SessionTemplate> _templates;

  @override
  void initState() {
    super.initState();
    _rows = ScanSessionService.getRows(widget.session.id);
    _templates = TemplateService.getAllTemplates();

    // Pre-select format based on session destination
    if (widget.session.destination == SessionDestination.googleSheets &&
        widget.session.spreadsheetId != null) {
      _selectedFormat = _ExportFormat.googleSheets;
    } else if (widget.session.destination == SessionDestination.localXlsx) {
      _selectedFormat = _ExportFormat.excel;
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  /// The columns used to preview / export. If a template is selected, use
  /// its columns; otherwise use the session's own columns.
  List<SessionColumn> get _activeColumns =>
      _selectedTemplate?.columns ?? widget.session.columns;

  /// Table data for the live preview (header + real rows).
  List<List<String>> get _previewTableData {
    final headers = _activeColumns.map((c) => c.name).toList();
    // Show first 3 real rows, otherwise fall back to sample rows
    final dataRows = _rows.take(3).map((r) {
      final vals = List<String>.from(r.values);
      // Pad or trim to match _activeColumns length
      while (vals.length < _activeColumns.length) {
        vals.add('—');
      }
      return vals.take(_activeColumns.length).toList();
    }).toList();

    if (dataRows.isEmpty) {
      // Synthetic sample rows
      dataRows.add(_sampleRow(0));
      dataRows.add(_sampleRow(1));
    }
    return [headers, ...dataRows];
  }

  List<String> _sampleRow(int idx) {
    return _activeColumns.map((c) {
      return switch (c.type) {
        SessionColumnType.scan => idx == 0 ? '8901234567890' : '4006381333931',
        SessionColumnType.manual => idx == 0 ? 'Product A' : 'Product B',
        SessionColumnType.timestamp =>
          idx == 0 ? '12 May 2026, 09:00' : '12 May 2026, 09:01',
        SessionColumnType.increment => '${idx + 1}',
        SessionColumnType.fixed => c.fixedValue ?? 'Value',
        SessionColumnType.location => idx == 0 ? '37.422, -122.084' : '37.423, -122.085',
      };
    }).toList();
  }

  // ── Export actions ─────────────────────────────────────────────────────────

  Future<void> _doExport() async {
    if (_rows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('No rows to export yet.'),
          backgroundColor: context.themeError,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    HapticFeedback.mediumImpact();

    if (_selectedFormat == _ExportFormat.googleSheets) {
      await _doGoogleSheetsExport();
    } else if (_selectedFormat == _ExportFormat.excel) {
      _doExcelExport();
    } else {
      _doCsvExport();
    }
  }

  List<List<String>> _buildTableData() {
    // Use session's toTableData but re-header with _activeColumns if template selected
    final headers = _activeColumns.map((c) => c.name).toList();
    final dataRows = _rows.map((r) {
      final vals = List<String>.from(r.values);
      while (vals.length < _activeColumns.length) {
        vals.add('');
      }
      return vals.take(_activeColumns.length).toList();
    }).toList();
    return [headers, ...dataRows];
  }

  void _doCsvExport() {
    final parentContext = Navigator.of(context).context;
    Navigator.pop(context);
    ExportService.processExport<String>(
      context: parentContext,
      loadingMessage: 'Generating CSV…',
      generator: () async {
        final tableData = _buildTableData();
        return const ListToCsvConverter().convert(tableData);
      },
      fileExtension: 'csv',
      shareText: 'Scan session: ${widget.session.name}',
      onGetFileData: (csvString) async {
        final dir = await getTemporaryDirectory();
        final ts = DateTime.now().millisecondsSinceEpoch;
        final file = File('${dir.path}/session_$ts.csv');
        final bytes = Uint8List.fromList([
          0xEF,
          0xBB,
          0xBF,
          ...utf8.encode(csvString),
        ]);
        await file.writeAsBytes(bytes);
        return (file.path, bytes);
      },
    );
  }

  void _doExcelExport() {
    final parentContext = Navigator.of(context).context;
    Navigator.pop(context);
    ExportService.processExport<Uint8List>(
      context: parentContext,
      loadingMessage: 'Generating Excel…',
      generator: () async {
        final tableData = _buildTableData();
        final excel = Excel.createExcel();
        final sheet = excel['Session'];
        if (tableData.isNotEmpty) {
          for (int c = 0; c < tableData.first.length; c++) {
            sheet
                .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0))
                .value = TextCellValue(
              tableData.first[c],
            );
          }
        }
        for (int r = 1; r < tableData.length; r++) {
          for (int c = 0; c < tableData[r].length; c++) {
            sheet
                .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r))
                .value = TextCellValue(
              tableData[r][c],
            );
          }
        }
        return Uint8List.fromList(excel.encode()!);
      },
      fileExtension: 'xlsx',
      shareText: 'Scan session: ${widget.session.name}',
      onGetFileData: (bytes) async {
        final dir = await getTemporaryDirectory();
        final ts = DateTime.now().millisecondsSinceEpoch;
        final file = File('${dir.path}/session_$ts.xlsx');
        await file.writeAsBytes(bytes);
        return (file.path, bytes);
      },
    );
  }

  Future<void> _doGoogleSheetsExport() async {
    if (widget.session.spreadsheetId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No spreadsheet connected. Set destination in session setup.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isExporting = true);

    try {
      final tableData = _buildTableData();
      final headers = tableData.isNotEmpty ? tableData.first : <String>[];
      final dataRows = tableData.length > 1
          ? tableData.sublist(1)
          : <List<String>>[];

      await GoogleSheetsService.instance.appendWithHeaders(
        widget.session.spreadsheetId!,
        widget.session.sheetName!,
        headers,
        dataRows,
      );

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Synced ${dataRows.length} rows to Google Sheets.'),
          backgroundColor: const Color(0xFF16A34A),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sync failed: $e'),
          backgroundColor: context.themeError,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.themeBg,
      appBar: AppBar(
        backgroundColor: context.themeCard,
        elevation: 0,
        scrolledUnderElevation: 1,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: context.themeTextPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Export & Templates',
          style: TextStyle(
            color: context.themeTextPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      bottomNavigationBar: _BottomExportBar(
        rowCount: _rows.length,
        format: _selectedFormat,
        isExporting: _isExporting,
        onExport: _doExport,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
        children: [
          // ── Format Picker ────────────────────────────────────────────────────
          _SectionLabel(label: 'Export Format'),
          const SizedBox(height: 10),
          _FormatPicker(
            selected: _selectedFormat,
            isConnected:
                widget.session.destination == SessionDestination.googleSheets &&
                widget.session.spreadsheetId != null,
            onSelect: (f) {
              HapticFeedback.selectionClick();
              setState(() => _selectedFormat = f);
            },
          ),

          const SizedBox(height: 28),

          // ── Template Gallery ─────────────────────────────────────────────────
          Row(
            children: [
              Expanded(child: _SectionLabel(label: 'Column Templates')),
              if (_selectedTemplate != null)
                GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _selectedTemplate = null);
                  },
                  child: Text(
                    'Clear',
                    style: TextStyle(
                      color: context.themeAccent,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Tap a template to preview its columns in the export.',
            style: TextStyle(color: context.themeTextSecondary, fontSize: 12),
          ),
          const SizedBox(height: 12),
          _TemplateGallery(
            templates: _templates,
            selected: _selectedTemplate,
            onSelect: (t) {
              HapticFeedback.selectionClick();
              setState(() {
                _selectedTemplate = _selectedTemplate?.id == t.id ? null : t;
              });
            },
          ),

          const SizedBox(height: 28),

          // ── Live Preview ─────────────────────────────────────────────────────
          Row(
            children: [
              Expanded(child: _SectionLabel(label: 'Data Preview')),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: context.themeAccent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _selectedTemplate != null
                      ? _selectedTemplate!.name
                      : 'Session columns',
                  style: TextStyle(
                    color: context.themeAccent,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _LivePreviewTable(tableData: _previewTableData),

          const SizedBox(height: 80), // Space for bottom bar
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: TextStyle(
        color: context.themeTextSecondary,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.0,
      ),
    );
  }
}

// ── Format Picker ─────────────────────────────────────────────────────────────

class _FormatPicker extends StatelessWidget {
  final _ExportFormat selected;
  final bool isConnected;
  final ValueChanged<_ExportFormat> onSelect;

  const _FormatPicker({
    required this.selected,
    required this.isConnected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _FormatCard(
            icon: Icons.table_rows_rounded,
            label: 'CSV',
            sublabel: 'Spreadsheet compatible',
            color: const Color(0xFF16A34A),
            isSelected: selected == _ExportFormat.csv,
            onTap: () => onSelect(_ExportFormat.csv),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _FormatCard(
            icon: Icons.grid_on_rounded,
            label: 'Excel',
            sublabel: '.xlsx format',
            color: const Color(0xFF10B981),
            isSelected: selected == _ExportFormat.excel,
            onTap: () => onSelect(_ExportFormat.excel),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _FormatCard(
            icon: Icons.table_chart_rounded,
            customIcon: SvgPicture.asset(
              'assets/sheets.svg',
              width: 18,
              height: 18,
            ),
            label: 'Sheets',
            sublabel: isConnected ? 'Connected' : 'Not linked',
            color: const Color(0xFF1B5FCC),
            isSelected: selected == _ExportFormat.googleSheets,
            badge: isConnected ? null : '!',
            onTap: () => onSelect(_ExportFormat.googleSheets),
          ),
        ),
      ],
    );
  }
}

class _FormatCard extends StatelessWidget {
  final IconData icon;
  final Widget? customIcon;
  final String label;
  final String sublabel;
  final Color color;
  final bool isSelected;
  final String? badge;
  final VoidCallback onTap;

  const _FormatCard({
    required this.icon,
    this.customIcon,
    required this.label,
    required this.sublabel,
    required this.color,
    required this.isSelected,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.1) : context.themeCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? color : context.themeBorder,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: customIcon ?? Icon(icon, size: 18, color: color),
                ),
                if (badge != null)
                  Positioned(
                    right: -4,
                    top: -4,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: context.themeWarm,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          badge!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 9),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? color : context.themeTextPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              sublabel,
              style: TextStyle(color: context.themeTextSecondary, fontSize: 10),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Template Gallery ──────────────────────────────────────────────────────────

class _TemplateGallery extends StatelessWidget {
  final List<SessionTemplate> templates;
  final SessionTemplate? selected;
  final ValueChanged<SessionTemplate> onSelect;

  const _TemplateGallery({
    required this.templates,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 114,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemCount: templates.length,
        itemBuilder: (context, i) {
          final t = templates[i];
          final isSelected = selected?.id == t.id;
          return _TemplateCard(
            template: t,
            isSelected: isSelected,
            onTap: () => onSelect(t),
          );
        },
      ),
    );
  }
}

class _TemplateCard extends StatelessWidget {
  final SessionTemplate template;
  final bool isSelected;
  final VoidCallback onTap;

  const _TemplateCard({
    required this.template,
    required this.isSelected,
    required this.onTap,
  });

  static const _teal = Color(0xFF006A6B);

  IconData _iconFor(String name) {
    return switch (name) {
      'inventory_2_rounded' => Icons.inventory_2_rounded,
      'people_rounded' => Icons.people_rounded,
      'confirmation_number_rounded' => Icons.confirmation_number_rounded,
      'devices_rounded' => Icons.devices_rounded,
      'sell_rounded' => Icons.sell_rounded,
      _ => Icons.grid_view_rounded,
    };
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 130,
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: isSelected ? _teal.withValues(alpha: 0.08) : context.themeCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? _teal : context.themeBorder,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? _teal.withValues(alpha: 0.15)
                        : context.themeSurface,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    _iconFor(template.icon),
                    size: 17,
                    color: isSelected ? _teal : context.themeTextSecondary,
                  ),
                ),
                const Spacer(),
                if (isSelected)
                  Icon(Icons.check_circle_rounded, size: 16, color: _teal),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              template.name,
              style: TextStyle(
                color: isSelected ? _teal : context.themeTextPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 3),
            Text(
              template.columnSummary,
              style: TextStyle(color: context.themeTextSecondary, fontSize: 10),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Live Preview Table ────────────────────────────────────────────────────────

class _LivePreviewTable extends StatelessWidget {
  final List<List<String>> tableData;

  const _LivePreviewTable({required this.tableData});

  @override
  Widget build(BuildContext context) {
    if (tableData.isEmpty) return const SizedBox.shrink();

    return AppCard(
      padding: EdgeInsets.zero,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: MediaQuery.of(context).size.width - 32,
          ),
          child: Column(
            children: [
              for (int r = 0; r < tableData.length; r++) ...[
                _PreviewRow(
                  cells: tableData[r],
                  isHeader: r == 0,
                  isSample: r > 0,
                ),
                if (r < tableData.length - 1)
                  Divider(height: 1, color: context.themeBorder),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PreviewRow extends StatelessWidget {
  final List<String> cells;
  final bool isHeader;
  final bool isSample;

  const _PreviewRow({
    required this.cells,
    required this.isHeader,
    this.isSample = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: isHeader
          ? context.themeAccent.withValues(alpha: 0.06)
          : Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: cells.map((cell) {
          return Container(
            width: 110,
            margin: const EdgeInsets.only(right: 16),
            child: Text(
              cell,
              style: TextStyle(
                color: isHeader
                    ? context.themeAccent
                    : isSample
                    ? context.themeTextSecondary
                    : context.themeTextPrimary,
                fontSize: isHeader ? 11 : 12,
                fontWeight: isHeader ? FontWeight.w700 : FontWeight.w400,
                fontFamily: isHeader ? null : 'monospace',
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── Bottom Export Bar ─────────────────────────────────────────────────────────

class _BottomExportBar extends StatelessWidget {
  final int rowCount;
  final _ExportFormat format;
  final bool isExporting;
  final VoidCallback onExport;

  const _BottomExportBar({
    required this.rowCount,
    required this.format,
    required this.isExporting,
    required this.onExport,
  });

  String get _buttonLabel {
    final suffix = rowCount > 0 ? '$rowCount rows' : 'no data';
    return switch (format) {
      _ExportFormat.csv => 'Export $suffix as CSV',
      _ExportFormat.excel => 'Export $suffix as Excel',
      _ExportFormat.googleSheets => 'Sync $suffix to Sheets',
    };
  }

  Color _buttonColor(BuildContext context) => switch (format) {
    _ExportFormat.csv => const Color(0xFF16A34A),
    _ExportFormat.excel => const Color(0xFF10B981),
    _ExportFormat.googleSheets => const Color(0xFF1B5FCC),
  };

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(
          color: context.themeCard,
          border: Border(top: BorderSide(color: context.themeBorder)),
        ),
        child: FilledButton(
          onPressed: (rowCount == 0 || isExporting) ? null : onExport,
          style: FilledButton.styleFrom(
            backgroundColor: _buttonColor(context),
            minimumSize: const Size(double.infinity, 52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: isExporting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                )
              : Text(
                  _buttonLabel,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
        ),
      ),
    );
  }
}
