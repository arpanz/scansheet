import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/services/google_sheets_service.dart';
import '../../core/services/scan_history_service.dart';
import '../../core/services/scan_session_service.dart';
import '../../core/services/sheet_summary.dart';
import '../../core/services/sync_queue_service.dart';
import '../../core/utils/app_router.dart';
import '../../core/widgets/ss.dart';
import '../scan/screens/read_code_screen.dart';
import '../scan/screens/scan_session_screen.dart';
import '../sheet/new_sheet_screen.dart';
import '../sheet/sheet_actions.dart';
import '../settings/screens/connect_sheets_screen.dart';
import '../settings/screens/settings_screen.dart';
import '../sheet/sheet_view_screen.dart';
import '../sync/plan_limits.dart';
import '../sync/sync_banner.dart';

/// Home tab. Busy state per docs/design/mocks/Home.dc.html, first run per
/// HomeEmpty.dc.html, dark per HomeDark.dc.html (all through tokens).
class HomeScreen extends StatelessWidget {
  final VoidCallback onSeeAll;
  const HomeScreen({super.key, required this.onSeeAll});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        ScanSessionService.changes,
        SyncQueueService.stats,
        GoogleSheetsService.instance.signedInNotifier,
      ]),
      builder: (context, _) {
        final sheets = SheetSummary.all();
        final firstRun = sheets.every((s) => s.rowCount == 0);
        return firstRun
            ? _FirstRunHome(sheets: sheets)
            : _BusyHome(sheets: sheets, onSeeAll: onSeeAll);
      },
    );
  }
}

void _open(BuildContext context, Widget page) =>
    Navigator.of(context).push(FadeSlideRoute(page: page));

String _initial() {
  final user = GoogleSheetsService.instance.currentUser;
  final name = user?.displayName?.trim();
  if (name != null && name.isNotEmpty) return name[0];
  final email = user?.email.trim() ?? '';
  return email.isNotEmpty ? email[0] : 'S';
}

class _Header extends StatelessWidget {
  final Widget eyebrow;
  final String title;
  const _Header({required this.eyebrow, required this.title});

  @override
  Widget build(BuildContext context) {
    return SsPageHeader(
      title: title,
      eyebrow: eyebrow,
      trailing: SsAvatar(
        initial: _initial(),
        onTap: () => _open(context, const SettingsScreen()),
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────── Busy home

class _BusyHome extends StatelessWidget {
  final List<SheetSummary> sheets;
  final VoidCallback onSeeAll;
  const _BusyHome({required this.sheets, required this.onSeeAll});

  @override
  Widget build(BuildContext context) {
    final current = SheetSummary.inProgress(sheets);
    final recent = sheets.where((s) => s != current).take(3).toList();
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        children: [
          _Header(
            eyebrow: _TodayLine(sheets: sheets),
            title: 'Your sheets',
          ),
          const SizedBox(height: 18),
          const SyncBanner(),
          const UsageMeter(),
          if (current != null) ...[
            _InProgressCard(sheet: current),
            const SizedBox(height: 18),
          ],
          const _QuickTiles(),
          if (recent.isNotEmpty) ...[
            const SizedBox(height: 18),
            SsSectionHeader(
              'Recent sheets',
              action: 'See all',
              onAction: onSeeAll,
            ),
            const SizedBox(height: 4),
            SsListGroup(
              children: [for (final s in recent) _SheetRow(sheet: s)],
            ),
          ],
        ],
      ),
    );
  }
}

/// "● Today 46 rows · all synced"
class _TodayLine extends StatelessWidget {
  final List<SheetSummary> sheets;
  const _TodayLine({required this.sheets});

  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    final today = sheets.fold<int>(0, (n, s) => n + s.rowsToday);
    final stats = SyncQueueService.stats.value;
    final (Color dot, String status) = stats.failedCount > 0
        ? (c.error, '${stats.failedCount} not synced')
        : stats.pendingCount > 0
        ? (c.amber, '${stats.pendingCount} syncing')
        : (c.emerald, 'all synced');
    return Row(
      children: [
        SsDot(color: dot),
        const SizedBox(width: 6),
        Flexible(
          child: Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: 'Today '),
                TextSpan(
                  text: '$today',
                  style: SsText.mono(size: 13, color: c.ink),
                ),
                TextSpan(text: '${today == 1 ? ' row' : ' rows'} · $status'),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _InProgressCard extends StatelessWidget {
  final SheetSummary sheet;
  const _InProgressCard({required this.sheet});

  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    final syncLine = !sheet.isSheets
        ? 'Saved on phone'
        : sheet.failed > 0
        ? '${sheet.failed} not synced'
        : sheet.pending > 0
        ? 'Syncing ${sheet.pending}…'
        : 'Synced ${relativeTime(sheet.lastActivity)}';
    void resume() => _open(context, ScanSessionScreen(session: sheet.session));

    return Container(
      decoration: BoxDecoration(
        color: c.hero,
        borderRadius: BorderRadius.circular(SsRadius.xl),
        border: Border.all(color: c.heroLine),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            right: -40,
            top: -40,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    SsColors.brandLime.withValues(
                      alpha: context.isDark ? 0.18 : 0.22,
                    ),
                    SsColors.brandLime.withValues(alpha: 0),
                  ],
                  stops: const [0, 0.7],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const SsPill.live('IN PROGRESS'),
                    const Spacer(),
                    Text(syncLine, style: SsText.caption(color: c.heroMuted)),
                    const SizedBox(width: 2),
                    SizedBox.square(
                      dimension: 32,
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        iconSize: 18,
                        tooltip: 'Sheet actions',
                        onPressed: () =>
                            showSheetActions(context, sheet.session),
                        icon: Icon(LucideIcons.ellipsis, color: c.heroMuted),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            sheet.session.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: SsText.sans(
                              size: 20,
                              weight: FontWeight.w600,
                              spacing: -0.4,
                              color: context.isDark ? c.ink : Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            sheet.columnsLine,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: SsText.sans(size: 13, color: c.heroMuted),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${sheet.rowCount}',
                          style: SsText.mono(
                            size: 34,
                            spacing: -1,
                            height: 1,
                            color: context.isDark ? c.ink : Colors.white,
                          ),
                        ),
                        Text(
                          sheet.rowCount == 1 ? 'row' : 'rows',
                          style: SsText.caption(color: c.heroMuted),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: SsButton.lime(
                        'Resume scanning',
                        icon: ssScanIcon,
                        large: false,
                        onPressed: resume,
                      ),
                    ),
                    const SizedBox(width: 8),
                    SsIconButton(
                      LucideIcons.sheet,
                      size: 48,
                      tooltip: 'Open sheet',
                      color: Colors.white,
                      background: Colors.white.withValues(
                        alpha: context.isDark ? 0.08 : 0.1,
                      ),
                      onPressed: () => _open(
                        context,
                        SheetViewScreen(session: sheet.session),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickTiles extends StatelessWidget {
  const _QuickTiles();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _QuickTile(
            icon: SsIconTile.accent(context, LucideIcons.plus),
            title: 'New sheet',
            subtitle: 'Pick columns, then scan',
            onTap: () => _open(context, const NewSheetScreen()),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _QuickTile(
            icon: const SsIconTile(LucideIcons.zap),
            title: 'Read a code',
            subtitle: 'One-off, kept in history',
            onTap: () => _open(context, const ReadCodeScreen()),
          ),
        ),
      ],
    );
  }
}

class _QuickTile extends StatelessWidget {
  final Widget icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _QuickTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    return SsCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          icon,
          const SizedBox(height: 14),
          Text(title, style: SsText.label(color: c.ink)),
          const SizedBox(height: 2),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: SsText.caption(color: c.muted),
          ),
        ],
      ),
    );
  }
}

class _SheetRow extends StatelessWidget {
  final SheetSummary sheet;
  const _SheetRow({required this.sheet});

  @override
  Widget build(BuildContext context) {
    final Widget status = !sheet.isSheets
        ? Text(
            relativeTime(sheet.lastActivity),
            style: SsText.caption(color: context.ss.muted),
          )
        : sheet.failed > 0
        ? SsStatus('${sheet.failed} failed', kind: SsStatusKind.failed)
        : sheet.pending > 0
        ? SsStatus('${sheet.pending} queued', kind: SsStatusKind.queued)
        : const SsStatus('Synced');
    return SsListRow(
      leading: SsIconTile(sheetIcon(sheet.session.iconName), size: 38),
      title: sheet.session.name,
      subtitle:
          '${sheet.rowCount} ${sheet.rowCount == 1 ? 'row' : 'rows'} · ${sheet.destinationLabel}',
      trailing: status,
      onTap: () => _open(context, SheetViewScreen(session: sheet.session)),
    );
  }
}

// ───────────────────────────────────────────────────────────── First run

class _FirstRunHome extends StatefulWidget {
  final List<SheetSummary> sheets;
  const _FirstRunHome({required this.sheets});

  @override
  State<_FirstRunHome> createState() => _FirstRunHomeState();
}

class _FirstRunHomeState extends State<_FirstRunHome> {
  static const _tipKey = 'home_scan_tip_dismissed';
  bool _showTip = false;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (mounted) setState(() => _showTip = !(p.getBool(_tipKey) ?? false));
    });
  }

  Future<void> _dismissTip() async {
    setState(() => _showTip = false);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_tipKey, true);
  }

  @override
  Widget build(BuildContext context) {
    final current = SheetSummary.inProgress(widget.sheets);
    final signedIn = GoogleSheetsService.instance.isSignedIn;
    final readCode = ScanHistoryService.getAll().isNotEmpty;
    final steps = [
      _Step(
        title: 'Scan your first code',
        subtitle: 'Any barcode or QR nearby works',
        done: false,
        onTap: () => _open(
          context,
          current != null
              ? ScanSessionScreen(session: current.session)
              : const NewSheetScreen(),
        ),
      ),
      _Step(
        title: 'Connect Google Sheets',
        subtitle: 'Rows land in your sheet as you scan',
        done: signedIn,
        onTap: () => _open(context, const ConnectSheetsScreen()),
      ),
      _Step(
        title: 'Read a one-off code',
        subtitle: 'Links, Wi-Fi and contacts open right away',
        done: readCode,
        onTap: () => _open(context, const ReadCodeScreen()),
      ),
    ];
    final doneCount = steps.where((s) => s.done).length;
    final c = context.ss;

    return Stack(
      children: [
        SafeArea(
          bottom: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 120),
            children: [
              _Header(
                eyebrow: const Text('You’re all set'),
                title: 'Welcome to ScanSheet',
              ),
              const SizedBox(height: 18),
              current != null
                  ? _ReadyCard(sheet: current)
                  : const _CreateCard(),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Get the most out of it',
                      style: SsText.section(color: c.ink),
                    ),
                  ),
                  Text(
                    '$doneCount / ${steps.length}',
                    style: SsText.mono(
                      size: 12,
                      weight: FontWeight.w400,
                      color: c.muted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SsListGroup(
                children: [
                  for (var i = 0; i < steps.length; i++)
                    _StepRow(
                      step: steps[i],
                      next:
                          !steps[i].done &&
                          steps.indexWhere((s) => !s.done) == i,
                    ),
                ],
              ),
            ],
          ),
        ),
        if (_showTip)
          Positioned(
            left: 0,
            right: 0,
            bottom: 36,
            child: Center(child: _ScanTip(onDismiss: _dismissTip)),
          ),
      ],
    );
  }
}

class _ReadyCard extends StatelessWidget {
  final SheetSummary sheet;
  const _ReadyCard({required this.sheet});

  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    final cols = sheet.session.columns.take(3).toList();
    final dashed = BorderSide(color: c.strongBorder);
    return SsCard(
      radius: SsRadius.xl,
      padding: const EdgeInsets.all(18),
      onTap: () => _open(context, ScanSessionScreen(session: sheet.session)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SsPill('READY', background: c.chip, foreground: c.ink2),
              const Spacer(),
              Text(
                sheet.destinationLabel,
                style: SsText.caption(color: c.muted),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            sheet.session.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: SsText.sans(
              size: 20,
              weight: FontWeight.w600,
              spacing: -0.4,
              color: c.ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            sheet.columnsLine,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: SsText.sans(size: 13, color: c.muted),
          ),
          const SizedBox(height: 14),
          // Empty sheet preview: header row + one placeholder row.
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(SsRadius.md),
              border: Border.fromBorderSide(dashed),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                Container(
                  color: c.paper,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: _PreviewRow(
                    cells: ['#', for (final col in cols) col.name],
                    style: SsText.sans(
                      size: 11,
                      weight: FontWeight.w600,
                      spacing: 0.6,
                      color: c.muted,
                    ),
                    upper: true,
                  ),
                ),
                Divider(height: 1, color: c.strongBorder),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: _PreviewRow(
                    cells: ['1', for (final _ in cols) '—'],
                    style: SsText.mono(
                      size: 12,
                      weight: FontWeight.w400,
                      color: c.muted.withValues(alpha: 0.6),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewRow extends StatelessWidget {
  final List<String> cells;
  final TextStyle style;
  final bool upper;
  const _PreviewRow({
    required this.cells,
    required this.style,
    this.upper = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 34,
          child: Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Text(cells.first, style: style),
          ),
        ),
        for (final cell in cells.skip(1))
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                upper ? cell.toUpperCase() : cell,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style,
              ),
            ),
          ),
      ],
    );
  }
}

class _CreateCard extends StatelessWidget {
  const _CreateCard();

  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    return SsCard(
      radius: SsRadius.xl,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SsIconTile.accent(context, LucideIcons.plus),
          const SizedBox(height: 14),
          Text(
            'Make your first sheet',
            style: SsText.sans(
              size: 20,
              weight: FontWeight.w600,
              spacing: -0.4,
              color: c.ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Pick a template, choose where rows go, start scanning.',
            style: SsText.sans(size: 13, color: c.muted),
          ),
          const SizedBox(height: 16),
          SsButton(
            'New sheet',
            large: false,
            onPressed: () => _open(context, const NewSheetScreen()),
          ),
        ],
      ),
    );
  }
}

class _Step {
  final String title;
  final String subtitle;
  final bool done;
  final VoidCallback onTap;
  const _Step({
    required this.title,
    required this.subtitle,
    required this.done,
    required this.onTap,
  });
}

class _StepRow extends StatelessWidget {
  final _Step step;

  /// The first unfinished step gets the dark ring.
  final bool next;
  const _StepRow({required this.step, required this.next});

  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    return SsListRow(
      leading: step.done
          ? Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: c.emerald,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                LucideIcons.check,
                size: 15,
                color: Colors.white,
              ),
            )
          : Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: next ? c.ink : c.strongBorder,
                  width: 2,
                ),
              ),
            ),
      title: step.title,
      subtitle: step.subtitle,
      titleColor: step.done ? c.muted : null,
      chevron: true,
      onTap: step.onTap,
    );
  }
}

/// Coach mark pointing at the Scan button in the nav bar.
class _ScanTip extends StatelessWidget {
  final VoidCallback onDismiss;
  const _ScanTip({required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 236,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomCenter,
        children: [
          Positioned(
            bottom: -7,
            child: Transform.rotate(
              angle: 0.785,
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: SsColors.brandInk,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
            decoration: BoxDecoration(
              color: SsColors.brandInk,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: SsColors.brandInk.withValues(alpha: 0.3),
                  blurRadius: 34,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: SsColors.brandLime,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: SsColors.brandLime.withValues(alpha: 0.25),
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Tap here to scan your first code',
                    style: SsText.sans(
                      size: 14,
                      weight: FontWeight.w500,
                      height: 1.35,
                      color: Colors.white,
                    ),
                  ),
                ),
                SsIconButton(
                  LucideIcons.x,
                  size: 32,
                  tooltip: 'Dismiss tip',
                  color: SsColors.nightMuted,
                  onPressed: onDismiss,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
