import 'dart:io';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/ads/ad_manager.dart';
import '../../../core/services/scan_session_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../features/bulk_gen/services/export_service.dart';
import '../models/scan_session.dart';

/// Bottom sheet with CSV / Excel export options for a completed or in-progress session.
class SessionExportSheet extends StatelessWidget {
  final ScanSession session;

  const SessionExportSheet({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    final rows = ScanSessionService.getRows(session.id);
    final rowCount = rows.length;

    return Container(
      decoration: BoxDecoration(
        color: context.themeCard,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
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
              const SizedBox(height: 18),

              // Header
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: context.themeAccent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(
                      Icons.file_download_rounded,
                      color: context.themeAccent,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Export Session',
                          style: TextStyle(
                            color: context.themeTextPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          '$rowCount ${rowCount == 1 ? 'row' : 'rows'} · ${session.columnCount} columns',
                          style: TextStyle(
                            color: context.themeTextSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
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
              const SizedBox(height: 24),

              if (rowCount == 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: context.themeError.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: context.themeError.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          color: context.themeError,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'No rows collected yet. Scan some items first.',
                            style: TextStyle(
                              color: context.themeError,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // Export options
              Row(
                children: [
                  Expanded(
                    child: _ExportCard(
                      icon: Icons.table_rows_rounded,
                      label: 'CSV',
                      sublabel: 'Free',
                      color: const Color(0xFF16A34A),
                      enabled: rowCount > 0,
                      onTap: rowCount > 0
                          ? () => _exportCsv(context, session, rows)
                          : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _ExportCard(
                      icon: Icons.grid_on_rounded,
                      label: 'Excel',
                      sublabel: 'Free',
                      color: const Color(0xFF10B981),
                      enabled: rowCount > 0,
                      onTap: rowCount > 0
                          ? () => _exportExcel(context, session, rows)
                          : null,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Google Sheets — PRO teaser
              _SheetsTeaser(context: context),
            ],
          ),
        ),
      ),
    );
  }

  static void _exportCsv(
    BuildContext context,
    ScanSession session,
    List<SessionRow> rows,
  ) {
    // Grab the parent navigator's context BEFORE popping the sheet,
    // because after pop() this bottom sheet's context becomes unmounted.
    final parentContext = Navigator.of(context).context;
    Navigator.pop(context);
    ExportService.processExport<String>(
      context: parentContext,
      loadingMessage: 'Generating CSV…',
      generator: () async {
        final tableData = session.toTableData(rows);
        return const ListToCsvConverter().convert(tableData);
      },
      fileExtension: 'csv',
      shareText: 'Scan session: ${session.name}',
      onGetFileData: (csvString) async {
        final dir = await getTemporaryDirectory();
        final ts = DateTime.now().millisecondsSinceEpoch;
        final file = File('${dir.path}/session_$ts.csv');
        final bytes = Uint8List.fromList(csvString.codeUnits);
        await file.writeAsBytes(bytes);
        return (file.path, bytes);
      },
    );
  }

  static void _exportExcel(
    BuildContext context,
    ScanSession session,
    List<SessionRow> rows,
  ) {
    final parentContext = Navigator.of(context).context;
    Navigator.pop(context);
    ExportService.processExport<Uint8List>(
      context: parentContext,
      loadingMessage: 'Generating Excel…',
      generator: () async {
        final tableData = session.toTableData(rows);
        final excel = Excel.createExcel();
        final sheet = excel['Session'];

        // Header row
        if (tableData.isNotEmpty) {
          final headerRow = tableData.first;
          for (int c = 0; c < headerRow.length; c++) {
            sheet
                .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0))
                .value = TextCellValue(
              headerRow[c],
            );
          }
        }

        // Data rows
        for (int r = 1; r < tableData.length; r++) {
          final row = tableData[r];
          for (int c = 0; c < row.length; c++) {
            sheet
                .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r))
                .value = TextCellValue(
              row[c],
            );
          }
        }

        final encoded = excel.encode();
        return Uint8List.fromList(encoded!);
      },
      fileExtension: 'xlsx',
      shareText: 'Scan session: ${session.name}',
      onGetFileData: (bytes) async {
        final dir = await getTemporaryDirectory();
        final ts = DateTime.now().millisecondsSinceEpoch;
        final file = File('${dir.path}/session_$ts.xlsx');
        await file.writeAsBytes(bytes);
        return (file.path, bytes);
      },
    );
  }
}

class _ExportCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sublabel;
  final Color color;
  final bool enabled;
  final VoidCallback? onTap;

  const _ExportCard({
    required this.icon,
    required this.label,
    required this.sublabel,
    required this.color,
    required this.enabled,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            color: enabled
                ? color.withValues(alpha: 0.08)
                : context.themeSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: enabled
                  ? color.withValues(alpha: 0.3)
                  : context.themeBorder,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
            child: Column(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: enabled
                        ? color.withValues(alpha: 0.15)
                        : context.themeBorder,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    color: enabled ? color : context.themeTextSecondary,
                    size: 22,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  label,
                  style: TextStyle(
                    color: enabled
                        ? context.themeTextPrimary
                        : context.themeTextSecondary,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  sublabel,
                  style: TextStyle(
                    color: enabled ? color : context.themeTextSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
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

class _SheetsTeaser extends StatelessWidget {
  final BuildContext context;
  const _SheetsTeaser({required this.context});

  @override
  Widget build(BuildContext ctx) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => AdManager.onShowPaywall?.call(ctx),
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            color: ctx.themeSurface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: ctx.themeBorder),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFF16A34A).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.table_chart_rounded,
                    color: Color(0xFF16A34A),
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
                          Text(
                            'Google Sheets',
                            style: TextStyle(
                              color: ctx.themeTextPrimary,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF22C55E), Color(0xFF16A34A)],
                              ),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: const Text(
                              'PRO',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        'Sync directly to Google Sheets — coming soon',
                        style: TextStyle(
                          color: ctx.themeTextSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.lock_rounded,
                  size: 16,
                  color: ctx.themeTextSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
