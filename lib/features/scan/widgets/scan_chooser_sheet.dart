import 'package:flutter/material.dart';

import '../../../core/services/sheet_summary.dart';
import '../../../core/utils/app_router.dart';
import '../../../core/widgets/ss.dart';
import '../screens/read_code_screen.dart';
import '../screens/scan_session_screen.dart';
import '../../sheet/new_sheet_screen.dart';
import '../../team/join_team_screen.dart';

/// "Scan into…" chooser (docs/design/mocks/ScanChooser.dc.html), shown by the
/// Scan button when no sheet is in progress.
Future<void> showScanChooser(BuildContext context) {
  final navigator = Navigator.of(context);

  // Close the sheet first, then act from the caller's navigator so nothing
  // runs on the sheet's disposed context.
  void go(Widget page) {
    navigator.pop();
    navigator.push(FadeSlideRoute(page: page));
  }

  return showSsSheet(
    context,
    builder: (ctx) =>
        _ScanChooser(recent: SheetSummary.all().take(2).toList(), onOpen: go),
  );
}

class _ScanChooser extends StatelessWidget {
  final List<SheetSummary> recent;
  final ValueChanged<Widget> onOpen;

  const _ScanChooser({required this.recent, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Scan into…',
            style: SsText.sans(
              size: 20,
              weight: FontWeight.w600,
              spacing: -0.4,
              color: c.ink,
            ),
          ),
          if (recent.isNotEmpty) ...[
            const SizedBox(height: 14),
            SsListGroup(
              children: [
                for (var i = 0; i < recent.length; i++)
                  _RecentRow(
                    sheet: recent[i],
                    first: i == 0,
                    onTap: () =>
                        onOpen(ScanSessionScreen(session: recent[i].session)),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _ActionTile(
                  icon: LucideIcons.plus,
                  label: 'New sheet',
                  onTap: () => onOpen(const NewSheetScreen()),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ActionTile(
                  icon: LucideIcons.zap,
                  label: 'Just read a code',
                  onTap: () => onOpen(const ReadCodeScreen()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _ActionTile(
            icon: LucideIcons.users,
            label: 'Join a team sheet',
            onTap: () => onOpen(const JoinTeamScreen()),
          ),
          const SizedBox(height: 14),
          Text(
            'Tip: the scan button reopens a sheet you used in the last '
            '${SheetSummary.freshFor.inHours} hours. Hold it to choose.',
            textAlign: TextAlign.center,
            style: SsText.caption(color: c.muted),
          ),
        ],
      ),
    );
  }
}

class _RecentRow extends StatelessWidget {
  final SheetSummary sheet;
  final bool first;
  final VoidCallback onTap;

  const _RecentRow({
    required this.sheet,
    required this.first,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    final last = relativeTime(sheet.lastActivity);
    return SsListRow(
      leading: first
          ? SsIconTile(
              ssScanIcon,
              size: 40,
              background: SsColors.brandInk,
              color: SsColors.brandLime,
            )
          : SsIconTile(sheetIcon(sheet.session.iconName), size: 40),
      title: sheet.session.name,
      subtitle:
          '${sheet.rowCount} ${sheet.rowCount == 1 ? 'row' : 'rows'} · ${first ? 'last scan ${last.toLowerCase()}' : last}',
      trailing: Text(
        'Continue',
        style: SsText.sans(size: 13, weight: FontWeight.w600, color: c.emerald),
      ),
      onTap: onTap,
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    return SsCard(
      radius: 16,
      padding: const EdgeInsets.all(12),
      onTap: onTap,
      child: SizedBox(
        height: 70,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(icon, size: 22, color: c.ink),
            Text(
              label,
              maxLines: 2,
              style: SsText.sans(
                size: 14,
                weight: FontWeight.w600,
                height: 1.2,
                color: c.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
