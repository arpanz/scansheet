import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../core/services/scan_history_service.dart';
import '../../core/services/scan_session_service.dart';
import '../../core/services/sheet_summary.dart';
import '../../core/services/sync_queue_service.dart';
import '../../core/utils/app_router.dart';
import '../../core/widgets/ss.dart';
import '../lists/lists_view.dart';
import '../sheet/sheet_view_screen.dart';
import '../scan/screens/read_code_screen.dart';
import '../sheet/new_sheet_screen.dart';
import '../sheet/sheet_actions.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();

  /// Which tab Library shows; set from outside to switch it.
  static final tab = ValueNotifier<String>('sheets');
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _search = TextEditingController();
  String get _tab => LibraryScreen.tab.value;
  set _tab(String value) => LibraryScreen.tab.value = value;
  String _filter = 'all';
  final Set<String> _hiddenSheets = {};
  final Set<String> _hiddenHistory = {};

  @override
  void initState() {
    super.initState();
    LibraryScreen.tab.addListener(_onTab);
  }

  void _onTab() => setState(() => _filter = 'all');

  @override
  void dispose() {
    LibraryScreen.tab.removeListener(_onTab);
    _search.dispose();
    super.dispose();
  }

  Future<void> _push(Widget page) async {
    await Navigator.of(context).push(FadeSlideRoute(page: page));
  }

  Future<void> _deleteSheet(SheetSummary sheet) async {
    final id = sheet.session.id;
    setState(() => _hiddenSheets.add(id));
    var undone = false;
    final controller = showSsToast(
      context,
      '${sheet.session.name} deleted',
      action: 'Undo',
      onAction: () {
        undone = true;
        if (mounted) setState(() => _hiddenSheets.remove(id));
      },
    );
    await controller.closed;
    if (!undone) {
      await ScanSessionService.deleteSession(id);
      await SyncQueueService.clearForSession(id);
    }
    if (mounted) setState(() => _hiddenSheets.remove(id));
  }

  Future<void> _deleteHistory(ScanEntry entry) async {
    final key = _historyKey(entry);
    setState(() => _hiddenHistory.add(key));
    var undone = false;
    final controller = showSsToast(
      context,
      'Code deleted',
      action: 'Undo',
      onAction: () {
        undone = true;
        if (mounted) setState(() => _hiddenHistory.remove(key));
      },
    );
    await controller.closed;
    if (!undone) await ScanHistoryService.deleteEntry(entry);
    if (mounted) setState(() => _hiddenHistory.remove(key));
  }

  static String _historyKey(ScanEntry entry) =>
      '${entry.scannedAt.toIso8601String()}|${entry.raw}';

  @override
  Widget build(BuildContext context) {
    final listens = Listenable.merge([
      ScanSessionService.changes,
      ScanHistoryService.box.listenable(),
      SyncQueueService.stats,
      _search,
    ]);
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(onNewSheet: () => _push(const NewSheetScreen())),
            const SizedBox(height: 16),
            SsSegmented<String>(
              options: const [
                ('sheets', 'Sheets'),
                ('lists', 'Lists'),
                ('history', 'Code history'),
              ],
              value: _tab,
              onChanged: (value) => setState(() {
                _tab = value;
                _filter = 'all';
              }),
            ),
            const SizedBox(height: 16),
            _SearchField(
              controller: _search,
              placeholder: switch (_tab) {
                'sheets' => 'Search sheets',
                'lists' => 'Search lists',
                _ => 'Search scanned codes',
              },
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListenableBuilder(
                listenable: listens,
                builder: (context, _) {
                  final query = _search.text.trim().toLowerCase();
                  if (_tab == 'lists') return ListsView(query: query);
                  if (_tab == 'sheets') {
                    final all = SheetSummary.all()
                        .where((s) => !_hiddenSheets.contains(s.session.id))
                        .toList();
                    final filtered = all.where((s) {
                      if (query.isNotEmpty &&
                          !s.session.name.toLowerCase().contains(query)) {
                        return false;
                      }
                      return switch (_filter) {
                        'inprogress' => s.session.isActive,
                        'needssync' => s.pending > 0 || s.failed > 0,
                        _ => true,
                      };
                    }).toList();
                    return _SheetsList(
                      allCount: all.length,
                      filter: _filter,
                      summaries: filtered,
                      onFilter: (value) => setState(() => _filter = value),
                      onOpen: (s) => _push(SheetViewScreen(session: s.session)),
                      openCount: all.where((s) => s.session.isActive).length,
                      onMore: (s) => showSheetActions(context, s.session),
                      onToggle: (s) => s.session.isActive
                          ? finishSheet(context, s.session)
                          : reopenSheet(context, s.session),
                      onFinishAll: () => finishAllSheets(context),
                      onDelete: _deleteSheet,
                      onNewSheet: () => _push(const NewSheetScreen()),
                    );
                  }
                  final history = ScanHistoryService.getAll().where((entry) {
                    return !_hiddenHistory.contains(_historyKey(entry)) &&
                        (query.isEmpty ||
                            entry.raw.toLowerCase().contains(query));
                  }).toList();
                  return _HistoryList(
                    history: history,
                    onDelete: _deleteHistory,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onNewSheet});
  final VoidCallback onNewSheet;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 44,
    child: Row(
      children: [
        Expanded(
          child: Text(
            'Library',
            style: SsText.sans(
              size: 28,
              weight: FontWeight.w600,
              spacing: -0.8,
              color: context.ss.ink,
            ),
          ),
        ),
        Material(
          color: context.ss.ink,
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onNewSheet,
            child: SizedBox(
              width: 44,
              height: 44,
              child: Icon(LucideIcons.plus, size: 20, color: context.ss.onInk),
            ),
          ),
        ),
      ],
    ),
  );
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.placeholder});
  final TextEditingController controller;
  final String placeholder;

  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    return SizedBox(
      height: 48,
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          TextField(
            controller: controller,
            style: SsText.sans(size: 15, color: c.ink),
            decoration: InputDecoration(
              hintText: placeholder,
              hintStyle: SsText.sans(size: 15, color: c.muted),
              contentPadding: const EdgeInsets.fromLTRB(42, 14, 14, 14),
              filled: true,
              fillColor: c.surface,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: c.line),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: c.strongBorder),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 14),
            child: Icon(LucideIcons.search, size: 18, color: c.muted),
          ),
        ],
      ),
    );
  }
}

class _SheetsList extends StatelessWidget {
  const _SheetsList({
    required this.allCount,
    required this.filter,
    required this.summaries,
    required this.onFilter,
    required this.openCount,
    required this.onOpen,
    required this.onMore,
    required this.onToggle,
    required this.onFinishAll,
    required this.onDelete,
    required this.onNewSheet,
  });
  final int allCount;
  final int openCount;
  final String filter;
  final List<SheetSummary> summaries;
  final ValueChanged<String> onFilter;
  final ValueChanged<SheetSummary> onOpen;
  final ValueChanged<SheetSummary> onMore;
  final ValueChanged<SheetSummary> onToggle;
  final VoidCallback onFinishAll;
  final ValueChanged<SheetSummary> onDelete;
  final VoidCallback onNewSheet;

  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    if (allCount == 0) return _EmptySheets(onNewSheet: onNewSheet);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          // Left-aligned like the mock, not centred by the Column.
          child: Row(
            children: [
              _FilterChip(
                label: 'All · $allCount',
                selected: filter == 'all',
                onTap: () => onFilter('all'),
              ),
              const SizedBox(width: 6),
              _FilterChip(
                label: openCount == 0
                    ? 'In progress'
                    : 'In progress · $openCount',
                selected: filter == 'inprogress',
                onTap: () => onFilter('inprogress'),
              ),
              const SizedBox(width: 6),
              _FilterChip(
                label: 'Needs sync',
                selected: filter == 'needssync',
                onTap: () => onFilter('needssync'),
              ),
            ],
          ),
        ),
        if (openCount > 1) ...[
          const SizedBox(height: 10),
          _OpenSheetsNote(count: openCount, onFinishAll: onFinishAll),
        ],
        const SizedBox(height: 14),
        Expanded(
          child: summaries.isEmpty
              ? Center(
                  child: Text(
                    'No matching sheets',
                    style: SsText.sans(size: 14, color: c.muted),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.only(bottom: 28),
                  itemCount: summaries.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final summary = summaries[index];
                    return _SwipeSheet(
                      summary: summary,
                      onOpen: () => onOpen(summary),
                      onMore: () => onMore(summary),
                      onToggle: () => onToggle(summary),
                      onDelete: () => onDelete(summary),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    return Material(
      color: selected ? c.ink : c.surface,
      borderRadius: BorderRadius.circular(17),
      child: InkWell(
        borderRadius: BorderRadius.circular(17),
        onTap: onTap,
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(17),
            border: selected ? null : Border.all(color: c.line),
          ),
          child: Text(
            label,
            style: SsText.sans(
              size: 13,
              weight: FontWeight.w500,
              color: selected ? c.onInk : c.ink,
            ),
          ),
        ),
      ),
    );
  }
}

class _SwipeSheet extends StatelessWidget {
  const _SwipeSheet({
    required this.summary,
    required this.onOpen,
    required this.onMore,
    required this.onToggle,
    required this.onDelete,
  });
  final SheetSummary summary;
  final VoidCallback onOpen;
  final VoidCallback onMore;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => Dismissible(
    key: ValueKey(summary.session.id),
    direction: DismissDirection.horizontal,
    background: _SwipeAction(
      label: summary.session.isActive ? 'Finish' : 'Reopen',
      colorRole: _SwipeColor.edit,
      alignment: Alignment.centerLeft,
    ),
    secondaryBackground: const _SwipeAction(
      label: 'Delete',
      colorRole: _SwipeColor.delete,
      alignment: Alignment.centerRight,
    ),
    confirmDismiss: (direction) async {
      if (direction == DismissDirection.startToEnd) {
        onToggle();
      } else {
        onDelete();
      }
      return false;
    },
    child: _SheetCard(summary: summary, onTap: onOpen, onMore: onMore),
  );
}

enum _SwipeColor { edit, delete }

class _SwipeAction extends StatelessWidget {
  const _SwipeAction({
    required this.label,
    required this.colorRole,
    required this.alignment,
  });
  final String label;
  final _SwipeColor colorRole;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    final color = colorRole == _SwipeColor.delete ? c.error : c.track;
    return Container(
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(
        label,
        style: SsText.sans(
          size: 12,
          weight: FontWeight.w600,
          color: colorRole == _SwipeColor.delete ? Colors.white : c.ink,
        ),
      ),
    );
  }
}

class _SheetCard extends StatelessWidget {
  const _SheetCard({
    required this.summary,
    required this.onTap,
    required this.onMore,
  });
  final SheetSummary summary;
  final VoidCallback onTap;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    final session = summary.session;
    final active = session.isActive;
    final status = active
        ? SsStatus('In progress', kind: SsStatusKind.live)
        : summary.failed > 0
        ? SsStatus('${summary.failed} failed', kind: SsStatusKind.failed)
        : summary.pending > 0
        ? SsStatus('${summary.pending} queued', kind: SsStatusKind.queued)
        : const SsStatus('Synced', kind: SsStatusKind.synced);
    final subtitle =
        '${relativeTime(summary.lastActivity)} · ${summary.destinationLabel}';
    return GestureDetector(
      onLongPress: onMore,
      child: SsCard(
        radius: 18,
        padding: const EdgeInsets.all(14),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                SsIconTile(
                  sheetIcon(session.iconName),
                  size: 40,
                  background: active ? c.ink : c.chip,
                  color: active ? c.lime : c.ink,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        session.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: SsText.sans(
                          size: 15,
                          weight: FontWeight.w600,
                          color: c.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: SsText.sans(size: 12, color: c.muted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${summary.rowCount}',
                  style: SsText.mono(
                    size: 18,
                    weight: FontWeight.w500,
                    color: c.ink,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.only(top: 10),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: c.lineSoft)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      summary.columnsLine.isEmpty ? '—' : summary.columnsLine,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SsText.mono(size: 11, color: c.muted),
                    ),
                  ),
                  const SizedBox(width: 10),
                  status,
                  const SizedBox(width: 4),
                  SizedBox.square(
                    dimension: 28,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      iconSize: 18,
                      tooltip: 'Sheet actions',
                      onPressed: onMore,
                      icon: Icon(LucideIcons.ellipsis, color: c.muted),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Several sheets left "in progress" make the Scan button guess; offer to
/// finish them all in one tap.
class _OpenSheetsNote extends StatelessWidget {
  const _OpenSheetsNote({required this.count, required this.onFinishAll});
  final int count;
  final VoidCallback onFinishAll;

  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
      decoration: BoxDecoration(
        color: c.chip,
        borderRadius: BorderRadius.circular(SsRadius.md),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$count sheets are in progress. Scan continues the most recent.',
              style: SsText.sans(size: 13, color: c.ink2),
            ),
          ),
          TextButton(
            onPressed: onFinishAll,
            child: Text(
              'Finish all',
              style: SsText.sans(
                size: 13,
                weight: FontWeight.w600,
                color: c.emerald,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryList extends StatelessWidget {
  const _HistoryList({required this.history, required this.onDelete});
  final List<ScanEntry> history;
  final ValueChanged<ScanEntry> onDelete;

  @override
  Widget build(BuildContext context) {
    if (history.isEmpty) {
      final c = context.ss;
      return Center(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 60),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SsIconTile(LucideIcons.history, size: 52),
              const SizedBox(height: 14),
              Text(
                'No codes yet',
                style: SsText.sans(
                  size: 16,
                  weight: FontWeight.w600,
                  color: c.ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Codes you read outside a sheet land here.',
                textAlign: TextAlign.center,
                style: SsText.sans(size: 13, color: c.muted),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: 200,
                child: SsButton.secondary(
                  'Read a code',
                  icon: LucideIcons.zap,
                  expand: false,
                  onPressed: () => Navigator.of(
                    context,
                  ).push(FadeSlideRoute(page: const ReadCodeScreen())),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 28),
      children: [
        SsListGroup(
          children: [
            for (final entry in history)
              _HistoryRow(entry: entry, onDelete: () => onDelete(entry)),
          ],
        ),
      ],
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.entry, required this.onDelete});
  final ScanEntry entry;
  final VoidCallback onDelete;

  IconData get _icon => switch (entry.type) {
    'url' => LucideIcons.link,
    'wifi' => LucideIcons.wifi,
    'vcard' => LucideIcons.contact,
    'email' => LucideIcons.mail,
    'phone' => LucideIcons.phone,
    'sms' => LucideIcons.messageSquare,
    'geo' => LucideIcons.mapPin,
    _ => LucideIcons.alignLeft,
  };

  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    return Dismissible(
      key: ValueKey('${entry.scannedAt.toIso8601String()}|${entry.raw}'),
      direction: DismissDirection.endToStart,
      background: const _SwipeAction(
        label: 'Delete',
        colorRole: _SwipeColor.delete,
        alignment: Alignment.centerRight,
      ),
      confirmDismiss: (_) async {
        onDelete();
        return false;
      },
      child: SizedBox(
        height: 68,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              SsIconTile(_icon, size: 38, background: c.chip, color: c.ink),
              const SizedBox(width: 12),
              Expanded(
                child: InkWell(
                  onTap: () async {
                    await Clipboard.setData(ClipboardData(text: entry.raw));
                    if (context.mounted) showSsToast(context, 'Copied');
                  },
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.raw,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: SsText.mono(
                          size: 13,
                          weight: FontWeight.w500,
                          color: c.ink,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${_typeLabel(entry.type)} · ${relativeTime(entry.scannedAt)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: SsText.sans(size: 12, color: c.muted),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(
                width: 40,
                height: 40,
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () async {
                      await Clipboard.setData(ClipboardData(text: entry.raw));
                      if (context.mounted) showSsToast(context, 'Copied');
                    },
                    child: Icon(LucideIcons.copy, size: 18, color: c.ink2),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _typeLabel(String type) => switch (type) {
    'url' => 'Link',
    'wifi' => 'Wi-Fi',
    'vcard' => 'Contact',
    'geo' => 'Location',
    'sms' => 'SMS',
    'text' => 'Text',
    'phone' => 'Phone',
    'email' => 'Email',
    _ => type,
  };
}

class _EmptySheets extends StatelessWidget {
  const _EmptySheets({required this.onNewSheet});
  final VoidCallback onNewSheet;

  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _SheetIllustration(),
            const SizedBox(height: 20),
            Text(
              'No sheets yet',
              textAlign: TextAlign.center,
              style: SsText.sans(
                size: 15,
                weight: FontWeight.w600,
                color: c.ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Start from a template. To scan as a team, everyone picks the '
              'same Google spreadsheet.',
              textAlign: TextAlign.center,
              style: SsText.sans(size: 13, color: c.ink2),
            ),
            const SizedBox(height: 24),
            SsButton('New sheet', large: false, onPressed: onNewSheet),
          ],
        ),
      ),
    );
  }
}

class _SheetIllustration extends StatelessWidget {
  const _SheetIllustration();

  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    return Container(
      width: 150,
      decoration: BoxDecoration(
        border: Border.all(color: c.strongBorder, style: BorderStyle.none),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          _illustrationRow(c.surface, c.line),
          _illustrationRow(c.surface, c.lineSoft),
          _illustrationRow(c.limeRow, c.limeRow),
        ],
      ),
    );
  }

  Widget _illustrationRow(Color fill, Color line) => Container(
    height: 22,
    decoration: BoxDecoration(
      color: fill,
      border: Border(
        bottom: BorderSide(color: line, style: BorderStyle.solid),
      ),
    ),
  );
}
