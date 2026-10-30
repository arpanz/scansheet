import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/services/scan_session_service.dart';
import '../../core/services/scanning_preferences.dart';
import '../../core/widgets/ss.dart';
import '../scan/models/scan_session.dart';

/// A sheet's rows as a table, newest first, the newest highlighted. Tap a
/// row to edit it; long-press for Edit / Delete. Rows have no swipe
/// actions, so a sideways swipe only ever scrolls.
///
/// A few columns stretch to fill the width. More scroll sideways as one
/// table, or with # and the code column held still when [pinned].
/// [expand] fills its parent with a header that stays put and rows that
/// build as they scroll (the full-screen view).
class RowsTable extends StatefulWidget {
  const RowsTable({
    super.key,
    required this.session,
    required this.rows,
    required this.onTap,
    required this.onDelete,
    this.pinned = false,
    this.expand = false,
  });
  final ScanSession session;
  final List<SessionRow> rows;
  final ValueChanged<SessionRow> onTap;
  final ValueChanged<SessionRow> onDelete;
  final bool pinned;
  final bool expand;

  @override
  State<RowsTable> createState() => _RowsTableState();
}

class _RowsTableState extends State<RowsTable> {
  // Pinned and full screen: the two halves scroll down together.
  final _left = ScrollController();
  final _right = ScrollController();
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _left.addListener(() => _follow(_left, _right));
    _right.addListener(() => _follow(_right, _left));
  }

  void _follow(ScrollController from, ScrollController to) {
    if (_syncing || !to.hasClients || to.offset == from.offset) return;
    _syncing = true;
    to.jumpTo(from.offset);
    _syncing = false;
  }

  @override
  void dispose() {
    _left.dispose();
    _right.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    final rows = widget.rows;
    final columns = widget.session.columns;
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
    final code = widget.session.scanColumnIndices.firstOrNull ?? 0;
    final total = 44.0 + widths.fold<double>(0, (a, b) => a + b);
    final order = [for (var r = rows.length - 1; r >= 0; r--) r];

    final table = LayoutBuilder(
      builder: (context, box) {
        final fits = total <= box.maxWidth;
        final scale = fits ? box.maxWidth / total : 1.0;
        final numberWidth = 44 * scale;
        final w = [for (final width in widths) width * scale];
        final all = [for (var i = 0; i < columns.length; i++) i];
        final rest = [
          for (final i in all)
            if (i != code) i,
        ];

        // The pinned part's right edge, drawn on its rows rather than the
        // whole column so it stops where the rows do.
        final edge = BoxDecoration(
          border: Border(right: BorderSide(color: c.line)),
        );

        Widget line(int r, List<Widget> cells, {bool edged = false}) =>
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => widget.onTap(rows[r]),
              onLongPress: () => _showRowActions(context, rows[r]),
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                  color: r == rows.length - 1 ? c.limeRow : c.surface,
                  border: Border(bottom: BorderSide(color: c.lineSoft)),
                ),
                foregroundDecoration: edged ? edge : null,
                child: Row(children: cells),
              ),
            );

        Widget cell(int r, int i) => SizedBox(
          width: w[i],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              i < rows[r].values.length ? rows[r].values[i] : '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: SsText.mono(
                size: 13,
                weight: r == rows.length - 1
                    ? FontWeight.w600
                    : FontWeight.w400,
                color: c.ink,
              ),
            ),
          ),
        );

        Widget number(int r) => SizedBox(
          width: numberWidth,
          child: Padding(
            padding: const EdgeInsets.only(left: 14),
            child: Text(
              '${rows[r].rowIndex + 1}',
              style: SsText.mono(size: 12, color: c.muted),
            ),
          ),
        );

        Widget part(
          List<int> indices, {
          bool withNumber = false,
          bool edged = false,
          ScrollController? controller,
        }) {
          List<Widget> cellsOf(int r) => [
            if (withNumber) number(r),
            for (final i in indices) cell(r, i),
          ];
          final header = Container(
            height: 44,
            decoration: BoxDecoration(
              color: c.paper,
              border: Border(bottom: BorderSide(color: c.line)),
            ),
            foregroundDecoration: edged ? edge : null,
            child: Row(
              children: [
                if (withNumber)
                  SizedBox(width: numberWidth, child: _head('#', c)),
                for (final i in indices)
                  SizedBox(width: w[i], child: _head(columns[i].name, c)),
              ],
            ),
          );
          if (!widget.expand) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                header,
                for (final r in order) line(r, cellsOf(r), edged: edged),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              header,
              Expanded(
                child: ListView.builder(
                  controller: controller,
                  padding: EdgeInsets.zero,
                  itemExtent: 44,
                  itemCount: order.length,
                  itemBuilder: (_, k) =>
                      line(order[k], cellsOf(order[k]), edged: edged),
                ),
              ),
            ],
          );
        }

        if (fits) return part(all, withNumber: true, controller: _right);
        if (!widget.pinned) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: total,
              child: part(all, withNumber: true, controller: _right),
            ),
          );
        }
        return Row(
          crossAxisAlignment: widget.expand
              ? CrossAxisAlignment.stretch
              : CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: numberWidth + w[code],
              child: part(
                [code],
                withNumber: true,
                edged: true,
                controller: _left,
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: rest.fold<double>(0, (sum, i) => sum + w[i]),
                  child: part(rest, controller: _right),
                ),
              ),
            ),
          ],
        );
      },
    );
    if (widget.expand) return ColoredBox(color: c.surface, child: table);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(SsRadius.lg),
        border: Border.all(color: c.line),
      ),
      child: table,
    );
  }

  Future<void> _showRowActions(BuildContext context, SessionRow row) async {
    final action = await showSsSheet<String>(
      context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: SsListGroup(
          children: [
            SsListRow(
              title: 'Edit row',
              leading: SsIconTile(LucideIcons.pencil, size: 36),
              onTap: () => Navigator.pop(ctx, 'edit'),
            ),
            SsListRow(
              title: 'Delete row',
              titleColor: ctx.ss.error,
              leading: SsIconTile(
                LucideIcons.trash2,
                size: 36,
                color: ctx.ss.error,
              ),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (action == 'edit') widget.onTap(row);
    if (action == 'delete') widget.onDelete(row);
  }

  Widget _head(String label, SsColors c) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
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

/// "Pin code": holds # and the code column still while the rest scroll.
/// Off unless turned on; remembered on this phone.
class PinCodeToggle extends StatelessWidget {
  const PinCodeToggle({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    final prefs = context.watch<ScanningPreferences>();
    final on = prefs.pinCodeColumn;
    return Semantics(
      button: true,
      toggled: on,
      label: 'Pin code column',
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          prefs.setPinCodeColumn(!on);
        },
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: on ? c.emeraldTint : c.surface,
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: on ? c.emerald : c.line),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                on ? LucideIcons.pin : LucideIcons.pinOff,
                size: 14,
                color: on ? c.emerald : c.ink2,
              ),
              const SizedBox(width: 6),
              Text(
                'Pin code',
                style: SsText.sans(
                  size: 13,
                  weight: FontWeight.w600,
                  color: on ? c.emerald : c.ink2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Every row of a sheet, edge to edge, with a header that stays put. Turn
/// the phone sideways from here to see more columns at once.
class RowsFullScreen extends StatefulWidget {
  const RowsFullScreen({
    super.key,
    required this.session,
    required this.onEdit,
    required this.onDelete,
  });
  final ScanSession session;
  final ValueChanged<SessionRow> onEdit;
  final ValueChanged<SessionRow> onDelete;

  @override
  State<RowsFullScreen> createState() => _RowsFullScreenState();
}

class _RowsFullScreenState extends State<RowsFullScreen> {
  bool _landscape = false;

  // The app is portrait-only on Android (manifest); iPhone follows
  // Info.plist, so it gets its own choices back.
  static List<DeviceOrientation> get _usual =>
      defaultTargetPlatform == TargetPlatform.android
      ? const [DeviceOrientation.portraitUp]
      : const [];

  Future<void> _turn() async {
    HapticFeedback.selectionClick();
    setState(() => _landscape = !_landscape);
    await SystemChrome.setPreferredOrientations(
      _landscape
          ? const [
              DeviceOrientation.landscapeLeft,
              DeviceOrientation.landscapeRight,
            ]
          : _usual,
    );
  }

  @override
  void dispose() {
    if (_landscape) SystemChrome.setPreferredOrientations(_usual);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    final pinned = context.watch<ScanningPreferences>().pinCodeColumn;
    return Scaffold(
      backgroundColor: c.surface,
      body: SafeArea(
        bottom: false,
        child: ListenableBuilder(
          listenable: ScanSessionService.changes,
          builder: (context, _) {
            final session =
                ScanSessionService.getSession(widget.session.id) ??
                widget.session;
            final rows = ScanSessionService.getRows(session.id);
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 12, 6),
                  child: Row(
                    children: [
                      SsIconButton(
                        LucideIcons.minimize2,
                        tooltip: 'Exit full screen',
                        onPressed: () => Navigator.pop(context),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              session.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: SsText.sans(
                                size: 16,
                                weight: FontWeight.w600,
                                color: c.ink,
                              ),
                            ),
                            Text(
                              '${rows.length} ${rows.length == 1 ? 'row' : 'rows'}'
                              ' · tap a row to edit',
                              style: SsText.caption(color: c.muted),
                            ),
                          ],
                        ),
                      ),
                      const PinCodeToggle(),
                      const SizedBox(width: 6),
                      SsIconButton(
                        LucideIcons.rotateCw,
                        tooltip: _landscape
                            ? 'Turn upright'
                            : 'Turn sideways for more columns',
                        onPressed: _turn,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: rows.isEmpty
                      ? Center(
                          child: Text(
                            'No rows yet',
                            style: SsText.body(color: c.muted),
                          ),
                        )
                      : RowsTable(
                          session: session,
                          rows: rows,
                          onTap: widget.onEdit,
                          onDelete: widget.onDelete,
                          pinned: pinned,
                          expand: true,
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
