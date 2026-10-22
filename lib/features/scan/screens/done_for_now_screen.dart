import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart' hide Border, TextSpan;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/export_service.dart';
import '../../../core/services/scan_session_service.dart';
import '../../../core/services/sync_queue_service.dart';
import '../../../core/widgets/ss.dart';
import '../models/scan_session.dart';
import '../../sheet/sheet_actions.dart';

enum _ExportFormat { excel, csv }

class DoneForNowScreen extends StatefulWidget {
  final ScanSession session;
  final int addedThisVisit;
  final int totalRows;
  final DateTime? visitStarted;

  const DoneForNowScreen({
    super.key,
    required this.session,
    required this.addedThisVisit,
    required this.totalRows,
    this.visitStarted,
  });

  @override
  State<DoneForNowScreen> createState() => _DoneForNowScreenState();
}

class _DoneForNowScreenState extends State<DoneForNowScreen> {
  _ExportFormat _format = _ExportFormat.excel;

  int get _uniqueScans {
    final scanIndex = widget.session.scanColumnIndices.firstOrNull;
    if (scanIndex == null) return 0;
    return ScanSessionService.getRows(widget.session.id)
        .where((row) => row.values.length > scanIndex)
        .map((row) => row.values[scanIndex].trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .length;
  }

  Future<void> _openSheet() async {
    final id = widget.session.spreadsheetId;
    if (id == null || id.isEmpty) return;
    final uri = Uri.parse('https://docs.google.com/spreadsheets/d/$id');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// The sheet as a file in the selected format: (path, bytes, extension).
  Future<(String, Uint8List, String)?> _makeFile() async {
    final rows = ScanSessionService.getRows(widget.session.id);
    if (rows.isEmpty) {
      showSsToast(context, 'No rows to export yet.');
      return null;
    }
    final width = widget.session.columns.length;
    final table = <List<String>>[
      widget.session.columns.map((column) => column.name).toList(),
      for (final row in rows)
        [
          for (var i = 0; i < width; i++)
            i < row.values.length ? row.values[i] : '',
        ],
    ];

    final Uint8List bytes;
    final String ext;
    if (_format == _ExportFormat.csv) {
      ext = 'csv';
      bytes = Uint8List.fromList([
        0xEF, 0xBB, 0xBF, // UTF-8 BOM so Excel reads accents correctly
        ...utf8.encode(const ListToCsvConverter().convert(table)),
      ]);
    } else {
      ext = 'xlsx';
      final excel = Excel.createExcel();
      final sheet = excel[excel.getDefaultSheet() ?? 'Sheet1'];
      for (var r = 0; r < table.length; r++) {
        for (var c = 0; c < table[r].length; c++) {
          sheet
              .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r))
              .value = TextCellValue(
            table[r][c],
          );
        }
      }
      bytes = Uint8List.fromList(excel.encode()!);
    }
    final safeName = widget.session.name
        .replaceAll(RegExp(r'[^\w\- ]'), '')
        .trim();
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/${safeName.isEmpty ? 'ScanSheet' : safeName}.$ext',
    );
    await file.writeAsBytes(bytes);
    return (file.path, bytes, ext);
  }

  Future<void> _save() async {
    final made = await _makeFile();
    if (made == null || !mounted) return;
    final (path, bytes, ext) = made;
    await ExportService.saveFile(context, path, bytes, ext);
  }

  Future<void> _share() async {
    final made = await _makeFile();
    if (made == null) return;
    await ExportService.shareFile(made.$1, widget.session.name);
  }

  // Rebuild as queued rows reach the sheet ("N waiting" → "All N synced").
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: SyncQueueService.stats,
    builder: (context, _) => _build(context),
  );

  Widget _build(BuildContext context) {
    final c = context.ss;
    final isSheets =
        widget.session.destination == SessionDestination.googleSheets;
    final pending = isSheets
        ? SyncQueueService.pendingForSession(widget.session.id)
        : 0;
    final synced = (widget.totalRows - pending).clamp(0, widget.totalRows);
    final localFormat =
        widget.session.destination == SessionDestination.localXlsx
        ? 'Excel'
        : 'CSV';
    final visitMinutes = widget.visitStarted == null
        ? null
        : DateTime.now().difference(widget.visitStarted!).inMinutes;

    return Scaffold(
      backgroundColor: c.paper,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 44,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SsIconButton(
                    LucideIcons.arrowLeft,
                    onPressed: () => Navigator.pop(context),
                    size: 44,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'SAVED · STILL OPEN FOR MORE',
                style: SsText.eyebrow(color: c.emerald),
              ),
              const SizedBox(height: 8),
              Text(
                widget.session.name,
                style: SsText.title(color: c.ink),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 14,
                children: [
                  _Stat(
                    value: '${widget.totalRows}',
                    label: widget.totalRows == 1 ? 'row' : 'rows',
                    color: c,
                  ),
                  _Stat(value: '$_uniqueScans', label: 'unique', color: c),
                  if (visitMinutes != null)
                    _Stat(value: '$visitMinutes', label: 'min', color: c),
                ],
              ),
              const SizedBox(height: 22),
              SsCard(
                padding: const EdgeInsets.all(16),
                radius: 20,
                child: Column(
                  children: [
                    Row(
                      children: [
                        SsIconTile(
                          isSheets ? LucideIcons.sheet : LucideIcons.smartphone,
                          background: c.emeraldTint,
                          color: c.emerald,
                          size: 40,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isSheets
                                    ? 'In Google Sheets'
                                    : 'Saved on this phone',
                                style: SsText.label(color: c.ink),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                isSheets
                                    ? (pending == 0
                                          ? (synced == 1
                                                ? '1 row synced · My Drive'
                                                : 'All $synced rows synced · My Drive')
                                          : '$pending ${pending == 1 ? 'row' : 'rows'} waiting to sync · My Drive')
                                    : '$localFormat format',
                                style: SsText.sans(size: 13, color: c.muted),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        if (isSheets)
                          Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              color: c.emerald,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              LucideIcons.check,
                              size: 14,
                              color: c.onInk,
                            ),
                          ),
                      ],
                    ),
                    if (isSheets) ...[
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: _DestinationAction(
                              label: 'Open in Sheets',
                              icon: LucideIcons.externalLink,
                              onTap: _openSheet,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _DestinationAction(
                              label: 'Share with team',
                              icon: LucideIcons.userPlus,
                              onTap: () => showSsToast(
                                context,
                                'Team sheets are coming soon',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Need a file? Save a copy anytime',
                style: SsText.sans(
                  size: 13,
                  weight: FontWeight.w500,
                  color: c.ink2,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _FormatCard(
                      format: _ExportFormat.excel,
                      selected: _format == _ExportFormat.excel,
                      onTap: () =>
                          setState(() => _format = _ExportFormat.excel),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _FormatCard(
                      format: _ExportFormat.csv,
                      selected: _format == _ExportFormat.csv,
                      onTap: () => setState(() => _format = _ExportFormat.csv),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: SsButton.secondary(
                      'Save to Files',
                      onPressed: _save,
                      icon: LucideIcons.download,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SsButton.secondary(
                      'Share',
                      onPressed: _share,
                      icon: LucideIcons.share2,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              SsButton(
                'Done for now',
                onPressed: () =>
                    Navigator.of(context).popUntil((route) => route.isFirst),
                large: true,
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                ),
                child: Text(
                  'Keep scanning',
                  style: SsText.sans(
                    size: 15,
                    weight: FontWeight.w500,
                    color: c.ink,
                  ),
                ),
              ),
              // Finishing stops the Scan button from resuming this sheet.
              Center(
                child: TextButton.icon(
                  onPressed: () async {
                    final navigator = Navigator.of(context);
                    await finishSheet(context, widget.session);
                    navigator.popUntil((route) => route.isFirst);
                  },
                  icon: Icon(LucideIcons.circleCheck, size: 16, color: c.muted),
                  label: Text(
                    'Finish this sheet',
                    style: SsText.sans(size: 13, color: c.muted),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String value;
  final String label;
  final SsColors color;

  const _Stat({required this.value, required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(
      children: [
        TextSpan(
          text: value,
          style: SsText.mono(
            size: 14,
            weight: FontWeight.w600,
            color: color.ink,
          ),
        ),
        TextSpan(
          text: ' $label',
          style: SsText.sans(size: 14, color: color.ink2),
        ),
      ],
    ),
  );
}

class _DestinationAction extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _DestinationAction({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    return Material(
      color: c.chip,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: 44,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: SsText.sans(
                    size: 13,
                    weight: FontWeight.w600,
                    color: c.ink,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Icon(icon, size: 15, color: c.ink),
            ],
          ),
        ),
      ),
    );
  }
}

class _FormatCard extends StatelessWidget {
  final _ExportFormat format;
  final bool selected;
  final VoidCallback onTap;

  const _FormatCard({
    required this.format,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    final excel = format == _ExportFormat.excel;
    return Material(
      color: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: selected ? c.ink : c.line,
          width: selected ? 1.5 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 96,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Icon(
                      excel ? LucideIcons.table2 : LucideIcons.file,
                      size: 22,
                      color: c.ink,
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          excel ? 'Excel' : 'CSV',
                          style: SsText.label(color: c.ink),
                        ),
                        Text(
                          excel ? '.xlsx · formatted' : '.csv · plain text',
                          style: SsText.caption(color: c.muted),
                        ),
                      ],
                    ),
                  ],
                ),
                if (selected)
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: c.ink,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(LucideIcons.check, size: 12, color: c.lime),
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
