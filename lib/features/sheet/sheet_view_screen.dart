import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/models/sync_queue_item.dart';
import '../../core/services/list_check.dart';
import '../../core/services/lookup_list_service.dart';
import '../../core/services/scan_session_service.dart';
import '../../core/services/sheet_summary.dart';
import '../../core/services/sync_queue_service.dart';
import '../../core/utils/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/ss.dart';
import 'row_summary.dart';
import 'sheet_actions.dart';
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

  /// Which list count chip is on (it filters the rows below), or null.
  String? _check;

  /// The pick-list choice the rows are filtered to ("Damaged"), or null.
  String? _pick;

  bool _searching = false;

  /// Rows as a list (the default) or the full table; remembered for every
  /// sheet, since someone who wants the grid wants it everywhere.
  bool _table = false;
  static const _tableKey = 'sheet_rows_as_table';

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      final table = prefs.getBool(_tableKey) ?? false;
      if (mounted && table != _table) setState(() => _table = table);
    });
  }

  void _toggleTable() {
    final table = !_table;
    setState(() => _table = table);
    SharedPreferences.getInstance().then((p) => p.setBool(_tableKey, table));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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

  void _openOptions() => showSheetActions(
    context,
    ScanSessionService.getSession(widget.session.id) ?? widget.session,
    onDeleted: () => Navigator.of(context).pop(),
  );

  /// Type a code without the camera: the scanner's own flow (repeats, the
  /// list check, Qty merge) opens straight to its keyboard sheet.
  Future<void> _typeCode(ScanSession session) async {
    final before = ScanSessionService.getRowCount(session.id);
    await Navigator.of(context).push(
      FadeSlideRoute(page: ScanSessionScreen(session: session, typeOnly: true)),
    );
    if (!mounted) return;
    if (ScanSessionService.getRowCount(session.id) > before) {
      showSsToast(context, 'Row added');
    }
  }

  void _export(ScanSession session) => Navigator.of(context).push(
    FadeSlideRoute(
      page: DoneForNowScreen(
        session: session,
        addedThisVisit: 0,
        totalRows: ScanSessionService.getRowCount(session.id),
      ),
    ),
  );

  /// Changes one cell of a row in place (the newest row's − / + or its
  /// pick-list choice). Undo, since the stepper sits where thumbs land.
  Future<void> _setCell(
    ScanSession session,
    SessionRow row,
    int column,
    String value,
    String message,
  ) async {
    final values = List.of(row.values);
    while (values.length <= column) {
      values.add('');
    }
    if (values[column] == value) return;
    values[column] = value;
    await ScanSessionService.updateRow(
      session.id,
      row.copyWith(values: values),
    );
    if (!mounted) return;
    showSsToast(
      context,
      message,
      action: 'Undo',
      onAction: () => ScanSessionService.updateRow(session.id, row),
    );
  }

  void _toggleSearch() => setState(() {
    _searching = !_searching;
    if (!_searching) {
      _searchController.clear();
      _query = '';
    }
  });

  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    final session =
        ScanSessionService.getSession(widget.session.id) ?? widget.session;
    return Scaffold(
      backgroundColor: c.paper,
      // In the bottom bar slot, toasts (Undo) float above the bar.
      bottomNavigationBar: SafeArea(top: false, child: _actionBar(session)),
      body: SafeArea(
        bottom: false,
        child: ListenableBuilder(
          listenable: Listenable.merge([
            ScanSessionService.changes,
            SyncQueueService.stats,
          ]),
          builder: (context, _) => _content(c),
        ),
      ),
    );
  }

  Widget _content(SsColors c) {
    // Re-read so renames and setting changes show live.
    final session =
        ScanSessionService.getSession(widget.session.id) ?? widget.session;
    final rows = ScanSessionService.getRows(session.id);
    final list = LookupListService.get(session.lookupListId);
    final check = list == null ? null : ListCheck(list, session, rows);
    final scan = session.scanColumnIndices.firstOrNull ?? 0;
    final pickColumn = session.columns.indexWhere(
      (col) => col.type == SessionColumnType.pickList,
    );
    final qtyColumn = session.qtyColumnIndex;
    bool inView(SessionRow row) {
      if (_pick != null) {
        final v = pickColumn >= 0 && pickColumn < row.values.length
            ? row.values[pickColumn].trim()
            : '';
        if (v != _pick) return false;
      }
      if (check == null || _check == null) return true;
      final code = scan < row.values.length ? row.values[scan] : '';
      final on = check.list.lookup(code) != null;
      return switch (_check) {
        'notonlist' => !on,
        'here' => on,
        'match' => check.matchesExpected(code),
        _ => true,
      };
    }

    final query = _query.toLowerCase();
    final filtered = rows
        .where(
          (row) =>
              inView(row) &&
              (query.isEmpty ||
                  row.values.any((v) => v.toLowerCase().contains(query))),
        )
        .toList();
    final entriesView =
        check != null && (_check == 'notyet' || _check == 'off');
    final needsLook =
        check != null &&
        check.hasExpected &&
        _check == null &&
        _pick == null &&
        query.isEmpty &&
        check.offCount.isNotEmpty;
    final view = RowSummaries(session, filtered);
    final picks = pickColumn < 0
        ? const <String>[]
        : session.columns[pickColumn].choices;

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              _SheetHero(
                session: session,
                rows: rows,
                check: check,
                summaries: RowSummaries(session, rows),
                checkFilter: _check,
                pickFilter: _pick,
                searching: _searching,
                onSearch: _toggleSearch,
                onOptions: _openOptions,
                onCheck: (v) => setState(() => _check = _check == v ? null : v),
                onPick: (v) => setState(() => _pick = _pick == v ? null : v),
              ),
              const SizedBox(height: 12),
              SyncBanner(session: session),
              if (_searching || _query.isNotEmpty) ...[
                _searchField(c),
                const SizedBox(height: 12),
              ],
              if (needsLook) ...[
                _NeedsLook(
                  check: check,
                  onSeeAll: () => setState(() => _check = 'off'),
                ),
                const SizedBox(height: 16),
              ],
              if (rows.isNotEmpty) ...[
                _sectionLabel(c, view, entriesView),
                const SizedBox(height: 8),
              ],
              if (entriesView)
                _ListEntries(
                  check: check,
                  offCount: _check == 'off',
                  query: query,
                )
              else if (rows.isEmpty)
                _EmptyRows(
                  onScan: () => Navigator.of(context).push(
                    FadeSlideRoute(page: ScanSessionScreen(session: session)),
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
              else if (_table)
                _RowsTable(
                  session: session,
                  rows: filtered,
                  onTap: _editRow,
                  onDelete: _deleteRow,
                )
              else
                _RowsList(
                  session: session,
                  rows: filtered,
                  summaries: view,
                  newest: rows.last.rowIndex,
                  onTap: _editRow,
                  onDelete: _deleteRow,
                  onQty: qtyColumn < 0
                      ? null
                      : (row, qty, before) => _setCell(
                          session,
                          row,
                          qtyColumn,
                          '$qty',
                          'Qty $before → $qty',
                        ),
                  onPick: picks.isEmpty
                      ? null
                      : (row, choice) => _setCell(
                          session,
                          row,
                          pickColumn,
                          choice,
                          '${session.columns[pickColumn].name}: $choice',
                        ),
                ),
            ]),
          ),
        ),
      ],
    );
  }

  /// "Latest first · Bin B4-12": what the rows below are, values every row
  /// shares, and the list / table switch.
  Widget _sectionLabel(SsColors c, RowSummaries view, bool entriesView) {
    final title = entriesView
        ? (_check == 'off' ? 'Off count' : 'Not scanned yet')
        : _pick != null
        ? '$_pick only'
        : 'Latest first';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Expanded(
            child: Text.rich(
              TextSpan(
                style: SsText.sans(
                  size: 12,
                  weight: FontWeight.w600,
                  color: c.ink2,
                ),
                children: [
                  TextSpan(text: title),
                  if (!entriesView)
                    for (final s in view.shared) ...[
                      TextSpan(text: ' · ${s.name} '),
                      TextSpan(
                        text: s.value,
                        style: SsText.mono(
                          size: 12,
                          weight: FontWeight.w600,
                          color: c.ink,
                        ),
                      ),
                    ],
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (!entriesView) _viewToggle(c),
        ],
      ),
    );
  }

  Widget _searchField(SsColors c) => TextField(
    controller: _searchController,
    autofocus: _searching && _query.isEmpty,
    onChanged: (value) => setState(() => _query = value.trim()),
    decoration: InputDecoration(
      hintText: 'Search codes, names, notes…',
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

  /// Shows the view it switches to: the table icon while on the list.
  Widget _viewToggle(SsColors c) => DecoratedBox(
    decoration: BoxDecoration(
      color: c.surface,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: c.line),
    ),
    child: SsIconButton(
      _table ? LucideIcons.list : LucideIcons.table2,
      onPressed: _toggleTable,
      tooltip: _table ? 'Show as list' : 'Show as table',
      size: 40,
    ),
  );

  /// Scan more · Type · Open in Sheets (or the file export for sheets kept
  /// on the phone). File copies of a Sheets sheet live in the ⋯ menu.
  Widget _actionBar(ScanSession session) {
    final sheets = session.destination == SessionDestination.googleSheets;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: cBrandInk(context),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: cBrandInk(context).withValues(alpha: .22),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      // The bar is ink in both modes: draw its other buttons with dark
      // tokens so their labels stay light.
      child: Theme(
        data: AppTheme.darkTheme,
        child: Row(
          children: [
            Expanded(
              flex: 16,
              child: SsButton.lime(
                'Scan more',
                icon: ssScanIcon,
                large: false,
                onPressed: () => Navigator.of(context).push(
                  FadeSlideRoute(page: ScanSessionScreen(session: session)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 10,
              child: SsButton.secondary(
                'Type',
                icon: LucideIcons.keyboard,
                large: false,
                onPressed: () => _typeCode(session),
              ),
            ),
            const SizedBox(width: 4),
            SsIconButton(
              sheets ? LucideIcons.externalLink : LucideIcons.download,
              color: Colors.white,
              tooltip: sheets
                  ? 'Open in Google Sheets'
                  : 'Save or share a file',
              size: 48,
              onPressed: sheets
                  ? (session.spreadsheetId == null ? null : _openSheet)
                  : () => _export(session),
            ),
          ],
        ),
      ),
    );
  }
}

Color cBrandInk(BuildContext context) =>
    context.isDark ? SsColors.nightSurface : SsColors.brandInk;

/// List entries for the Not yet and Off count cards.
class _ListEntries extends StatelessWidget {
  final ListCheck check;
  final bool offCount;
  final String query;
  const _ListEntries({
    required this.check,
    required this.offCount,
    required this.query,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    final list = check.list;
    bool matches(List<String> row) =>
        query.isEmpty || row.any((v) => v.toLowerCase().contains(query));
    final items = offCount
        ? [
            for (final l in check.offCount)
              if (matches(l.row)) (l.row, l),
          ]
        : [
            for (final row in check.notScanned)
              if (matches(row)) (row, null),
          ];
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(28),
        child: Center(
          child: Text(
            offCount ? 'Every count matches so far' : 'Nothing left to scan',
            style: SsText.body(color: c.muted),
          ),
        ),
      );
    }
    return SsListGroup(
      children: [
        for (final (row, line) in items)
          SsListRow(
            title: list.titleFor(row),
            subtitle: line == null
                ? row[list.codeColumn]
                : '${row[list.codeColumn]} · ${line.counted} of ${line.expected}',
            trailing: line == null
                ? null
                : Text(
                    '${line.counted > line.expected ? '+' : '−'}'
                    '${(line.counted - line.expected).abs()}',
                    style: SsText.mono(
                      size: 15,
                      weight: FontWeight.w600,
                      color: line.counted > line.expected ? c.emerald : c.error,
                    ),
                  ),
          ),
      ],
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

/// Amber on the ink hero, the same in both themes.
const _heroAmber = Color(0xFFF2B45A);

/// Amber text that stays readable on light surfaces too.
Color _amberText(BuildContext context) =>
    context.isDark ? context.ss.amber : const Color(0xFF8A4B06);

/// The sheet's ink card: its name, where rows go, and a summary built from
/// the sheet's own columns. With a list: progress and match / off counts.
/// Without one: rows, units (with a Qty), the most common exception
/// ("8 Damaged") and today's scans.
class _SheetHero extends StatelessWidget {
  const _SheetHero({
    required this.session,
    required this.rows,
    required this.check,
    required this.summaries,
    required this.checkFilter,
    required this.pickFilter,
    required this.searching,
    required this.onSearch,
    required this.onOptions,
    required this.onCheck,
    required this.onPick,
  });
  final ScanSession session;
  final List<SessionRow> rows;
  final ListCheck? check;
  final RowSummaries summaries;
  final String? checkFilter;
  final String? pickFilter;
  final bool searching;
  final VoidCallback onSearch;
  final VoidCallback onOptions;
  final ValueChanged<String> onCheck;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    final text = context.isDark ? c.ink : Colors.white;
    final pending = SyncQueueService.pendingForSession(session.id);
    final failed = SyncQueueService.hasFailuresForSession(session.id);
    final (String status, Color tone) = switch (session.destination) {
      SessionDestination.googleSheets when failed => (
        'Sync issue · $pending waiting',
        _heroAmber,
      ),
      SessionDestination.googleSheets when pending > 0 => (
        'Syncing $pending…',
        c.heroMuted,
      ),
      SessionDestination.googleSheets => (
        'In Google Sheets',
        SsColors.brandLime,
      ),
      SessionDestination.localXlsx => ('On this phone · Excel', c.heroMuted),
      SessionDestination.localCsv => ('On this phone · CSV', c.heroMuted),
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: c.hero,
        borderRadius: BorderRadius.circular(SsRadius.xl),
        border: Border.all(color: c.heroLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _HeroButton(
                LucideIcons.arrowLeft,
                'Back',
                () => Navigator.pop(context),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SsText.sans(
                        size: 17,
                        weight: FontWeight.w600,
                        color: text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        SsDot(color: tone),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            status,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: SsText.sans(
                              size: 12,
                              weight: FontWeight.w600,
                              color: tone,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              _HeroButton(
                searching ? LucideIcons.x : LucideIcons.search,
                searching ? 'Close search' : 'Search rows',
                onSearch,
              ),
              const SizedBox(width: 6),
              _HeroButton(LucideIcons.ellipsis, 'Sheet options', onOptions),
            ],
          ),
          const SizedBox(height: 14),
          if (check case final check?)
            _checkSummary(context, check)
          else
            _tiles(),
        ],
      ),
    );
  }

  Widget _checkSummary(BuildContext context, ListCheck check) {
    final c = context.ss;
    final text = context.isDark ? c.ink : Colors.white;
    final chips = check.hasExpected
        ? [
            ('match', '${check.matching} match', false),
            ('off', '${check.offCount.length} off', check.offCount.isNotEmpty),
            ('notyet', '${check.notYet} to go', false),
          ]
        : [
            ('here', '${check.found} here', false),
            ('notyet', '${check.notYet} not yet', false),
            (
              'notonlist',
              '${check.notOnList.length} not on list',
              check.notOnList.isNotEmpty,
            ),
          ];
    return Row(
      children: [
        SizedBox.square(
          dimension: 60,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox.expand(
                child: CircularProgressIndicator(
                  value: check.progress,
                  strokeWidth: 7,
                  strokeCap: StrokeCap.round,
                  color: SsColors.brandLime,
                  backgroundColor: Colors.white.withValues(alpha: .1),
                ),
              ),
              Text(
                '${check.found}',
                style: SsText.mono(
                  size: 15,
                  weight: FontWeight.w600,
                  color: text,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text:
                          '${check.found} of ${check.total} '
                          '${check.hasExpected ? 'counted' : 'here'}',
                      style: SsText.sans(
                        size: 14,
                        weight: FontWeight.w600,
                        color: text,
                      ),
                    ),
                    TextSpan(
                      text: ' · ${check.list.name}',
                      style: SsText.sans(size: 14, color: c.heroMuted),
                    ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final (key, label, warn) in chips)
                    _HeroChip(
                      label,
                      warn: warn,
                      selected: checkFilter == key,
                      onTap: () => onCheck(key),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _tiles() {
    final today = RowSummaries.scannedOn(rows, DateTime.now());
    final last = rows.isEmpty
        ? null
        : rows.map((r) => r.scannedAt).reduce((a, b) => a.isAfter(b) ? a : b);
    final exception = summaries.exceptions.firstOrNull;
    final tiles = [
      _HeroTile(
        value: '${rows.length}',
        label: rows.length == 1 ? 'Row' : 'Rows',
        accent: true,
      ),
      if (summaries.units case final units?)
        _HeroTile(value: '$units', label: 'Units'),
      if (exception != null)
        _HeroTile(
          value: '${exception.count}',
          label: exception.value,
          warn: true,
          selected: pickFilter == exception.value,
          onTap: () => onPick(exception.value),
        ),
      if (today > 0 || last == null)
        _HeroTile(value: '$today', label: 'Today')
      else
        _HeroTile(value: relativeTime(last), label: 'Last scan'),
    ].take(3).toList();
    return Row(
      children: [
        for (final (i, tile) in tiles.indexed) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(child: tile),
        ],
      ],
    );
  }
}

class _HeroButton extends StatelessWidget {
  const _HeroButton(this.icon, this.tooltip, this.onPressed);
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(12),
          child: SizedBox.square(
            dimension: 40,
            child: Icon(
              icon,
              size: 20,
              color: context.isDark ? c.ink : Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

/// One stat on the hero; tappable ones (an exception) filter the rows.
class _HeroTile extends StatelessWidget {
  const _HeroTile({
    required this.value,
    required this.label,
    this.accent = false,
    this.warn = false,
    this.selected = false,
    this.onTap,
  });
  final String value;
  final String label;
  final bool accent;
  final bool warn;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    final fg = warn
        ? _heroAmber
        : accent
        ? SsColors.brandLime
        : context.isDark
        ? c.ink
        : Colors.white;
    final numeric = int.tryParse(value) != null;
    final tile = AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
      decoration: BoxDecoration(
        color: warn
            ? _heroAmber.withValues(alpha: selected ? .3 : .16)
            : Colors.white.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: selected ? fg : Colors.transparent),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 28,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: numeric
                    ? SsText.mono(size: 22, weight: FontWeight.w600, color: fg)
                    : SsText.sans(size: 16, weight: FontWeight.w600, color: fg),
              ),
            ),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: SsText.sans(size: 12, color: warn ? fg : c.heroMuted),
          ),
        ],
      ),
    );
    if (onTap == null) return tile;
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(onTap: onTap, child: tile),
    );
  }
}

class _HeroChip extends StatelessWidget {
  const _HeroChip(
    this.label, {
    required this.warn,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool warn;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    final (Color bg, Color fg) = selected
        ? (SsColors.brandLime, SsColors.brandInk)
        : warn
        ? (_heroAmber.withValues(alpha: .16), _heroAmber)
        : (
            Colors.white.withValues(alpha: .08),
            context.isDark ? c.ink : Colors.white,
          );
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
            child: Text(
              label,
              style: SsText.sans(
                size: 12,
                weight: warn || selected ? FontWeight.w600 : FontWeight.w500,
                color: fg,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Stock lines counted but not as expected, pinned above the rows so they
/// get a second look before the count is done.
class _NeedsLook extends StatelessWidget {
  const _NeedsLook({required this.check, required this.onSeeAll});
  final ListCheck check;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    final amber = _amberText(context);
    final lines = check.offCount;
    final list = check.list;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Needs a look · ${lines.length}',
                  style: SsText.sans(
                    size: 12,
                    weight: FontWeight.w600,
                    color: amber,
                  ),
                ),
              ),
              if (lines.length > 3)
                TextButton(onPressed: onSeeAll, child: const Text('See all')),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(SsRadius.lg),
            border: Border.all(color: c.amber.withValues(alpha: .4)),
          ),
          child: Column(
            children: [
              for (final (i, l) in lines.take(3).indexed) ...[
                if (i > 0) Divider(height: 1, color: c.lineSoft),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              list.titleFor(l.row),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: SsText.label(color: c.ink),
                            ),
                            Text(
                              RowSummaries.formatCode(l.row[list.codeColumn]),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: SsText.mono(size: 12, color: c.ink2),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: c.amber.withValues(alpha: .14),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          l.counted < l.expected
                              ? '${l.expected - l.counted} short of ${l.expected}'
                              : '${l.counted - l.expected} over ${l.expected}',
                          style: SsText.sans(
                            size: 12,
                            weight: FontWeight.w600,
                            color: amber,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '${l.counted}',
                        style: SsText.mono(
                          size: 18,
                          weight: FontWeight.w600,
                          color: amber,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Rows as a list, newest first: what was scanned and how many, the cells
/// that differ underneath. Rows scanned while a Same value column changed
/// (the room moved) group under each value. The newest row can be fixed in
/// place: − / + for its Qty, or its pick-list choice.
class _RowsList extends StatelessWidget {
  const _RowsList({
    required this.session,
    required this.rows,
    required this.summaries,
    required this.newest,
    required this.onTap,
    required this.onDelete,
    this.onQty,
    this.onPick,
  });
  final ScanSession session;
  final List<SessionRow> rows;
  final RowSummaries summaries;

  /// rowIndex of the sheet's newest row, drawn editable when in view.
  final int newest;
  final ValueChanged<SessionRow> onTap;
  final ValueChanged<SessionRow> onDelete;
  final void Function(SessionRow row, int qty, String before)? onQty;
  final void Function(SessionRow row, String choice)? onPick;

  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    final display = rows.reversed.toList();
    final grouped = summaries.groupColumn >= 0;
    final groups = grouped
        ? summaries.runs(display)
        : [(value: '', rows: display)];
    final sheets = session.destination == SessionDestination.googleSheets;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (gi, g) in groups.indexed) ...[
          if (grouped) ...[
            if (gi > 0) const SizedBox(height: 14),
            _GroupHeader(
              value: g.value.isEmpty
                  ? 'No ${session.columns[summaries.groupColumn].name}'
                  : g.value,
              rows: g.rows,
              summaries: summaries,
            ),
            const SizedBox(height: 8),
          ],
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(SsRadius.lg),
              border: Border.all(color: c.line),
            ),
            child: Column(
              children: [
                for (final (i, row) in g.rows.indexed) ...[
                  if (i > 0) Divider(height: 1, color: c.lineSoft),
                  _swipe(
                    context,
                    row,
                    _RowCard(
                      row: row,
                      summary: summaries.of(row),
                      newest: row.rowIndex == newest,
                      status: sheets
                          ? SyncQueueService.get(
                              '${session.id}_${row.rowIndex}',
                            )?.status
                          : null,
                      stepSize: session.qtyColumnIndex < 0
                          ? 1
                          : session.columns[session.qtyColumnIndex].stepSize,
                      choices: onPick == null
                          ? const []
                          : session.columns
                                .firstWhere(
                                  (col) =>
                                      col.type == SessionColumnType.pickList,
                                )
                                .choices,
                      onTap: () => onTap(row),
                      onQty: onQty == null
                          ? null
                          : (qty, before) => onQty!(row, qty, before),
                      onPick: onPick == null
                          ? null
                          : (choice) => onPick!(row, choice),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _swipe(BuildContext context, SessionRow row, Widget child) {
    final c = context.ss;
    return Dismissible(
      key: ValueKey('${session.id}_${row.rowIndex}'),
      direction: DismissDirection.horizontal,
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          onTap(row);
          return false;
        }
        onDelete(row);
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
      child: child,
    );
  }
}

/// "Meeting room B · 16 · 2 damaged" over the rows scanned there.
class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.value,
    required this.rows,
    required this.summaries,
  });
  final String value;
  final List<SessionRow> rows;
  final RowSummaries summaries;

  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    final flagged = [
      for (final r in rows)
        if (summaries.of(r) case final s when s.pickIsException) s.pick!,
    ];
    final kinds = flagged.toSet();
    // Filtered to one choice, every row has it: the count says it all.
    final flag = flagged.isEmpty || flagged.length == rows.length
        ? ''
        : kinds.length == 1
        ? ' · ${flagged.length} ${kinds.single.toLowerCase()}'
        : ' · ${flagged.length} flagged';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Icon(LucideIcons.mapPin, size: 15, color: c.ink2),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: value,
                    style: SsText.sans(
                      size: 13,
                      weight: FontWeight.w600,
                      color: c.ink2,
                    ),
                  ),
                  TextSpan(
                    text: ' · ${rows.length}$flag',
                    style: SsText.mono(size: 12, color: c.muted),
                  ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _RowCard extends StatelessWidget {
  const _RowCard({
    required this.row,
    required this.summary,
    required this.newest,
    required this.status,
    required this.stepSize,
    required this.choices,
    required this.onTap,
    this.onQty,
    this.onPick,
  });
  final SessionRow row;
  final RowSummary summary;

  /// The sheet's latest row: highlighted, and editable in place.
  final bool newest;

  /// Google Sheets sync state; null for files or a row with nothing queued.
  final SyncStatus? status;
  final int stepSize;
  final List<String> choices;
  final VoidCallback onTap;
  final void Function(int qty, String before)? onQty;
  final ValueChanged<String>? onPick;

  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    final s = summary;
    final weight = newest ? FontWeight.w700 : FontWeight.w600;
    final rest = [
      ...s.details,
      if (row.notOnList) 'Not on list',
      relativeTime(row.scannedAt),
    ].join(' · ');
    final qty = s.qty == null ? null : int.tryParse(s.qty!);
    final stepper = newest && onQty != null && (qty != null || s.qty == null);
    final picker = newest && !stepper && onPick != null && choices.isNotEmpty;

    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          s.titleIsCode ? RowSummaries.formatCode(s.title) : s.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: s.titleIsCode
              ? SsText.mono(
                  size: newest ? 17 : 15,
                  weight: weight,
                  spacing: .3,
                  color: c.ink,
                )
              : SsText.sans(
                  size: newest ? 16 : 15,
                  weight: weight,
                  color: c.ink,
                ),
        ),
        const SizedBox(height: 2),
        Text.rich(
          TextSpan(
            children: [
              if (s.code != null) ...[
                TextSpan(
                  text: RowSummaries.formatCode(s.code!),
                  style: SsText.mono(size: 12, color: c.ink2),
                ),
                const TextSpan(text: ' · '),
              ],
              TextSpan(text: rest),
            ],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: SsText.caption(
            color: row.notOnList ? _amberText(context) : c.muted,
          ),
        ),
      ],
    );

    final trailing = <Widget>[
      if (row.locked)
        Tooltip(
          message: 'Over this month’s limit · kept on this phone',
          child: Icon(LucideIcons.lock, size: 16, color: c.muted),
        ),
      if (status == SyncStatus.failed)
        Tooltip(
          message: 'Not synced yet',
          child: Icon(LucideIcons.circleAlert, size: 16, color: c.error),
        )
      else if (status == SyncStatus.pending || status == SyncStatus.syncing)
        Tooltip(
          message: 'Waiting to sync',
          child: Icon(LucideIcons.clock, size: 16, color: c.amber),
        ),
      if (stepper) ...[
        _StepButton(
          LucideIcons.minus,
          'One less',
          (qty ?? 0) <= 0
              ? null
              : () => onQty!((qty! - stepSize).clamp(0, 1 << 31), s.qty ?? ''),
        ),
        SizedBox(
          width: 36,
          child: Text(
            s.qty ?? '0',
            textAlign: TextAlign.center,
            style: SsText.mono(size: 20, weight: FontWeight.w600, color: c.ink),
          ),
        ),
        _StepButton(
          LucideIcons.plus,
          'One more',
          () => onQty!((qty ?? 0) + stepSize, s.qty ?? ''),
          filled: true,
        ),
      ] else if (s.qty != null)
        Text(
          s.qty!,
          style: SsText.mono(size: 18, weight: FontWeight.w600, color: c.ink),
        )
      else if (s.pick != null && !picker)
        s.pickIsException
            ? Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: c.amber.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  s.pick!,
                  style: SsText.sans(
                    size: 12,
                    weight: FontWeight.w600,
                    color: _amberText(context),
                  ),
                ),
              )
            : Text(s.pick!, style: SsText.sans(size: 13, color: c.muted)),
    ];

    return Material(
      color: newest ? c.limeRow : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            14,
            newest ? 12 : 11,
            12,
            newest ? 12 : 11,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: info),
                  for (final w in trailing) ...[const SizedBox(width: 8), w],
                ],
              ),
              if (picker) ...[
                const SizedBox(height: 10),
                _ChoiceBar(choices: choices, selected: s.pick, onPick: onPick!),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton(
    this.icon,
    this.label,
    this.onPressed, {
    this.filled = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Opacity(
        opacity: onPressed == null ? .4 : 1,
        child: Material(
          color: filled ? c.ink : c.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: filled ? BorderSide.none : BorderSide(color: c.strongBorder),
          ),
          child: InkWell(
            onTap: onPressed == null
                ? null
                : () {
                    HapticFeedback.selectionClick();
                    onPressed!();
                  },
            borderRadius: BorderRadius.circular(14),
            child: SizedBox.square(
              dimension: 44,
              child: Icon(icon, size: 18, color: filled ? c.onInk : c.ink),
            ),
          ),
        ),
      ),
    );
  }
}

/// The newest row's pick-list, one tap to change it (Good · Damaged ·
/// Missing) without opening the edit sheet.
class _ChoiceBar extends StatelessWidget {
  const _ChoiceBar({
    required this.choices,
    required this.selected,
    required this.onPick,
  });
  final List<String> choices;
  final String? selected;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.line),
      ),
      child: Row(
        children: [
          for (final (i, choice) in choices.indexed) ...[
            if (i > 0) const SizedBox(width: 4),
            Expanded(
              child: Semantics(
                selected: choice == selected,
                button: true,
                child: Material(
                  color: choice == selected ? c.ink : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                  child: InkWell(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      onPick(choice);
                    },
                    borderRadius: BorderRadius.circular(9),
                    child: SizedBox(
                      height: 40,
                      child: Center(
                        child: Text(
                          choice,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: SsText.sans(
                            size: 13,
                            weight: choice == selected
                                ? FontWeight.w600
                                : FontWeight.w500,
                            color: choice == selected ? c.onInk : c.ink2,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
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
