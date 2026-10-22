import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/services/scan_session_service.dart';
import '../../core/services/sync_queue_service.dart';
import '../../core/utils/app_router.dart';
import '../../core/widgets/ss.dart';
import '../sync/sync_banner.dart';
import '../scan/models/scan_session.dart';
import '../scan/screens/done_for_now_screen.dart';
import '../scan/screens/scan_session_screen.dart';

class SheetViewScreen extends StatefulWidget {
  const SheetViewScreen({super.key, required this.session});
  final ScanSession session;

  @override
  State<SheetViewScreen> createState() => _SheetViewScreenState();
}

class _SheetViewScreenState extends State<SheetViewScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _rename() async {
    final name = await showSsTextPrompt(
      context,
      title: 'Rename sheet',
      label: 'Sheet name',
      initial: widget.session.name,
    );
    if (name == null || !mounted) return;
    await ScanSessionService.saveSession(widget.session.copyWith(name: name));
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete sheet?'),
        content: Text(
          '“${widget.session.name}” and its rows will be deleted from this phone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ScanSessionService.deleteSession(widget.session.id);
    await SyncQueueService.clearForSession(widget.session.id);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _openSheet() async {
    final id = widget.session.spreadsheetId;
    if (id == null || id.isEmpty) return;
    await launchUrl(
      Uri.parse('https://docs.google.com/spreadsheets/d/$id'),
      mode: LaunchMode.externalApplication,
    );
  }

  Future<void> _editRow(SessionRow row) async {
    await showSsSheet<void>(
      context,
      builder: (_) => _EditRowSheet(session: widget.session, row: row),
    );
  }

  Future<void> _deleteRow(SessionRow row) async {
    await ScanSessionService.deleteRow(widget.session.id, row.rowIndex);
    if (!mounted) return;
    showSsToast(
      context,
      'Row deleted',
      action: 'Undo',
      onAction: () => ScanSessionService.addRow(widget.session.id, row),
    );
  }

  void _openOptions() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.ss.surface,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(LucideIcons.pencil),
              title: const Text('Rename sheet'),
              onTap: () {
                Navigator.pop(sheetContext);
                _rename();
              },
            ),
            ListTile(
              leading: const Icon(LucideIcons.trash2),
              title: const Text('Delete sheet'),
              textColor: context.ss.error,
              iconColor: context.ss.error,
              onTap: () {
                Navigator.pop(sheetContext);
                _delete();
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    final session =
        ScanSessionService.getSession(widget.session.id) ?? widget.session;
    return Scaffold(
      backgroundColor: c.paper,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListenableBuilder(
                listenable: Listenable.merge([
                  ScanSessionService.changes,
                  SyncQueueService.stats,
                ]),
                builder: (context, _) {
                  // Re-read so renames and setting changes show live.
                  final session =
                      ScanSessionService.getSession(widget.session.id) ??
                      widget.session;
                  final rows = ScanSessionService.getRows(session.id);
                  final filtered = rows
                      .where(
                        (row) =>
                            _query.isEmpty ||
                            row.values.any(
                              (v) => v.toLowerCase().contains(
                                _query.toLowerCase(),
                              ),
                            ),
                      )
                      .toList();
                  final pending = SyncQueueService.pendingForSession(
                    session.id,
                  );
                  final failed = SyncQueueService.hasFailuresForSession(
                    session.id,
                  );
                  final unique = rows
                      .map((r) => r.values.isEmpty ? '' : r.values.first)
                      .where((v) => v.isNotEmpty)
                      .toSet()
                      .length;
                  final qtyIndex = session.qtyColumnIndex;
                  final totalQty = qtyIndex < 0
                      ? rows.length
                      : rows.fold<int>(
                          0,
                          (sum, row) =>
                              sum +
                              (row.values.length > qtyIndex
                                  ? int.tryParse(row.values[qtyIndex]) ?? 0
                                  : 0),
                        );
                  return CustomScrollView(
                    slivers: [
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                        sliver: SliverList(
                          delegate: SliverChildListDelegate([
                            _header(session),
                            const SizedBox(height: 16),
                            SyncBanner(session: session),
                            Row(
                              children: [
                                Expanded(
                                  child: _Metric(
                                    value: '${rows.length}',
                                    label: 'Rows',
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _Metric(
                                    value: '$unique',
                                    label: 'Unique items',
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _Metric(
                                    value: '$totalQty',
                                    label: 'Total qty',
                                  ),
                                ),
                              ],
                            ),
                            if (session.destination ==
                                SessionDestination.googleSheets) ...[
                              const SizedBox(height: 14),
                              _DestinationStrip(
                                session: session,
                                pending: pending,
                                failed: failed,
                                onOpen: session.spreadsheetId == null
                                    ? null
                                    : _openSheet,
                              ),
                            ],
                            const SizedBox(height: 14),
                            _searchField(c),
                            const SizedBox(height: 14),
                            if (rows.isEmpty)
                              _EmptyRows(
                                onScan: () => Navigator.of(context).push(
                                  FadeSlideRoute(
                                    page: ScanSessionScreen(session: session),
                                  ),
                                ),
                              )
                            else if (filtered.isEmpty)
                              Padding(
                                padding: const EdgeInsets.all(28),
                                child: Center(
                                  child: Text(
                                    'No matching rows',
                                    style: SsText.body(color: c.muted),
                                  ),
                                ),
                              )
                            else
                              _RowsTable(
                                session: session,
                                rows: filtered,
                                onTap: _editRow,
                                onDelete: _deleteRow,
                              ),
                          ]),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            _actionBar(session),
          ],
        ),
      ),
    );
  }

  Widget _header(ScanSession session) => SizedBox(
    height: 44,
    child: Row(
      children: [
        SsIconButton(
          LucideIcons.arrowLeft,
          onPressed: () => Navigator.pop(context),
          tooltip: 'Back',
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            session.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: SsText.sans(
              size: 20,
              weight: FontWeight.w600,
              spacing: -0.4,
              color: context.ss.ink,
            ),
          ),
        ),
        SsIconButton(
          LucideIcons.ellipsis,
          onPressed: _openOptions,
          tooltip: 'Sheet options',
        ),
      ],
    ),
  );

  Widget _searchField(SsColors c) => TextField(
    controller: _searchController,
    onChanged: (value) => setState(() => _query = value.trim()),
    decoration: InputDecoration(
      hintText: 'Search codes, notes…',
      prefixIcon: const Icon(LucideIcons.search, size: 18),
      filled: true,
      fillColor: c.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(SsRadius.md),
        borderSide: BorderSide(color: c.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(SsRadius.md),
        borderSide: BorderSide(color: c.line),
      ),
    ),
  );

  Widget _actionBar(ScanSession session) => Container(
    margin: const EdgeInsets.fromLTRB(20, 8, 20, 18),
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      color: cBrandInk(context),
      borderRadius: BorderRadius.circular(22),
      boxShadow: [
        BoxShadow(
          color: cBrandInk(context).withValues(alpha: .22),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
      ],
    ),
    child: Row(
      children: [
        Expanded(
          child: SsButton.lime(
            'Scan more',
            icon: ssScanIcon,
            large: false,
            onPressed: () => Navigator.of(
              context,
            ).push(FadeSlideRoute(page: ScanSessionScreen(session: session))),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: SsButton(
            'Export',
            kind: SsButtonKind.ghost,
            icon: LucideIcons.download,
            large: false,
            onPressed: () => Navigator.of(context).push(
              FadeSlideRoute(
                page: DoneForNowScreen(
                  session: session,
                  addedThisVisit: 0,
                  totalRows: ScanSessionService.getRowCount(session.id),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

Color cBrandInk(BuildContext context) =>
    context.isDark ? SsColors.nightSurface : SsColors.brandInk;

class _Metric extends StatelessWidget {
  const _Metric({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: SsText.mono(
              size: 22,
              weight: FontWeight.w500,
              spacing: -.5,
              color: c.ink,
            ),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: SsText.sans(size: 12, color: c.muted),
          ),
        ],
      ),
    );
  }
}

class _DestinationStrip extends StatelessWidget {
  const _DestinationStrip({
    required this.session,
    required this.pending,
    required this.failed,
    required this.onOpen,
  });
  final ScanSession session;
  final int pending;
  final bool failed;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    final kind = failed
        ? SsStatusKind.failed
        : pending > 0
        ? SsStatusKind.queued
        : SsStatusKind.synced;
    final status = failed
        ? 'Sync issue · $pending waiting'
        : pending > 0
        ? '$pending rows waiting to sync'
        : 'Synced to Google Sheets';
    return Material(
      color: c.emeraldTint,
      borderRadius: BorderRadius.circular(SsRadius.md),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(SsRadius.md),
        child: SizedBox(
          height: 48,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Icon(LucideIcons.refreshCw, size: 18, color: c.emeraldDeep),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    status,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SsText.sans(
                      size: 13,
                      weight: FontWeight.w500,
                      color: c.emeraldDeep,
                    ),
                  ),
                ),
                SsStatus(
                  failed
                      ? 'Failed'
                      : pending > 0
                      ? 'Queued'
                      : 'Synced',
                  kind: kind,
                ),
                if (onOpen != null) ...[
                  const SizedBox(width: 8),
                  Icon(
                    LucideIcons.externalLink,
                    size: 15,
                    color: c.emeraldDeep,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RowsTable extends StatelessWidget {
  const _RowsTable({
    required this.session,
    required this.rows,
    required this.onTap,
    required this.onDelete,
  });
  final ScanSession session;
  final List<SessionRow> rows;
  final ValueChanged<SessionRow> onTap;
  final ValueChanged<SessionRow> onDelete;

  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    final columns = session.columns;
    // Fit the longest value (mono ≈ 8.6 px/char at 14) or the header,
    // so codes are never cut off; very long text still ellipsizes.
    final widths = [
      for (var i = 0; i < columns.length; i++)
        (rows.fold<int>(
                  columns[i].name.length,
                  (n, r) => i < r.values.length && r.values[i].length > n
                      ? r.values[i].length
                      : n,
                ) *
                8.6 +
            28)
            .clamp(80.0, 260.0),
    ];
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(SsRadius.lg),
        border: Border.all(color: c.line),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: widths.fold<double>(44, (a, b) => a + b),
          child: Column(
            children: [
              Container(
                color: c.paper,
                child: Row(
                  children: [
                    SizedBox(width: 44, child: _head('#', c)),
                    for (var i = 0; i < columns.length; i++)
                      SizedBox(
                        width: widths[i],
                        child: _head(columns[i].name, c),
                      ),
                  ],
                ),
              ),
              for (var index = rows.length - 1; index >= 0; index--)
                Dismissible(
                  key: ValueKey('${session.id}_${rows[index].rowIndex}'),
                  direction: DismissDirection.horizontal,
                  confirmDismiss: (direction) async {
                    if (direction == DismissDirection.startToEnd) {
                      onTap(rows[index]);
                      return false;
                    }
                    onDelete(rows[index]);
                    return true;
                  },
                  background: Container(
                    color: c.emeraldTint,
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.only(left: 18),
                    child: Icon(LucideIcons.pencil, color: c.emerald),
                  ),
                  secondaryBackground: Container(
                    color: c.error,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 18),
                    child: const Icon(LucideIcons.trash2, color: Colors.white),
                  ),
                  child: InkWell(
                    onTap: () => onTap(rows[index]),
                    child: Container(
                      height: 44,
                      decoration: BoxDecoration(
                        color: index == rows.length - 1 ? c.limeRow : c.surface,
                        border: Border(bottom: BorderSide(color: c.lineSoft)),
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 44,
                            child: Padding(
                              padding: const EdgeInsets.only(left: 14),
                              child: Text(
                                '${rows[index].rowIndex + 1}',
                                style: SsText.mono(size: 12, color: c.muted),
                              ),
                            ),
                          ),
                          for (var i = 0; i < columns.length; i++)
                            SizedBox(
                              width: widths[i],
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                child: Text(
                                  i < rows[index].values.length
                                      ? rows[index].values[i]
                                      : '',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: SsText.mono(
                                    size: 13,
                                    weight: index == rows.length - 1
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                    color: c.ink,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _head(String label, SsColors c) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
    child: Text(
      label.toUpperCase(),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: SsText.sans(
        size: 10,
        weight: FontWeight.w600,
        spacing: .6,
        color: c.muted,
      ),
    ),
  );
}

class _EmptyRows extends StatelessWidget {
  const _EmptyRows({required this.onScan});
  final VoidCallback onScan;
  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(SsRadius.lg),
        border: Border.all(color: c.line),
      ),
      child: Column(
        children: [
          Icon(LucideIcons.scanLine, size: 30, color: c.emerald),
          const SizedBox(height: 10),
          Text(
            'Your rows will show up here',
            style: SsText.label(color: c.ink),
          ),
          const SizedBox(height: 4),
          Text(
            'Start scanning to add the first item to this sheet.',
            textAlign: TextAlign.center,
            style: SsText.sans(size: 13, color: c.muted),
          ),
          const SizedBox(height: 14),
          SsButton.lime('Start scanning', icon: ssScanIcon, onPressed: onScan),
        ],
      ),
    );
  }
}

class _EditRowSheet extends StatefulWidget {
  const _EditRowSheet({required this.session, required this.row});
  final ScanSession session;
  final SessionRow row;
  @override
  State<_EditRowSheet> createState() => _EditRowSheetState();
}

class _EditRowSheetState extends State<_EditRowSheet> {
  late final List<TextEditingController> _controllers;
  late final List<int> _numbers;
  late final List<String> _values;

  @override
  void initState() {
    super.initState();
    _values = List.generate(
      widget.session.columns.length,
      (i) => i < widget.row.values.length ? widget.row.values[i] : '',
    );
    _controllers = List.generate(
      _values.length,
      (i) => TextEditingController(text: _values[i]),
    );
    _numbers = _values.map((v) => int.tryParse(v) ?? 0).toList();
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    for (var i = 0; i < _values.length; i++) {
      final column = widget.session.columns[i];
      if (column.isNumeric) {
        _values[i] = '${_numbers[i]}';
      } else if (column.type != SessionColumnType.pickList) {
        _values[i] = _controllers[i].text;
      }
    }
    await ScanSessionService.updateRow(
      widget.session.id,
      widget.row.copyWith(values: List.of(_values)),
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Edit row', style: SsText.section(color: c.ink)),
          const SizedBox(height: 16),
          for (var i = 0; i < widget.session.columns.length; i++) ...[
            _field(i, c),
            const SizedBox(height: 14),
          ],
          const SizedBox(height: 4),
          SsButton('Save changes', onPressed: _save),
        ],
      ),
    );
  }

  Widget _field(int i, SsColors c) {
    final column = widget.session.columns[i];
    if (column.type == SessionColumnType.pickList &&
        column.choices.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(column.name, style: SsText.label(color: c.ink)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final choice in column.choices)
                ChoiceChip(
                  label: Text(choice),
                  selected: _values[i] == choice,
                  onSelected: (_) => setState(() => _values[i] = choice),
                ),
            ],
          ),
        ],
      );
    }
    if (column.isNumeric) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(column.name, style: SsText.label(color: c.ink)),
          const SizedBox(height: 6),
          SsStepper(
            value: _numbers[i],
            min: 0,
            step: column.stepSize,
            onChanged: (value) => setState(() => _numbers[i] = value),
          ),
        ],
      );
    }
    return TextField(
      controller: _controllers[i],
      decoration: InputDecoration(
        labelText: column.name,
        filled: true,
        fillColor: c.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(SsRadius.md),
        ),
      ),
    );
  }
}
