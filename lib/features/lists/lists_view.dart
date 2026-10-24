import 'package:flutter/material.dart';

import '../../core/services/lookup_list_service.dart';
import '../../core/services/scan_session_service.dart';
import '../../core/services/sheet_summary.dart';
import '../../core/services/team_service.dart';
import '../../core/services/usage_service.dart';
import '../../core/utils/app_router.dart';
import '../../core/widgets/ss.dart';
import 'list_import_screen.dart';

/// Library › Lists: the code lists sheets check against.
class ListsView extends StatelessWidget {
  final String query;
  const ListsView({super.key, required this.query});

  Future<void> _add(BuildContext context) => Navigator.of(
    context,
  ).push(FadeSlideRoute(page: const ListImportScreen()));

  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    return ValueListenableBuilder(
      valueListenable: LookupListService.changes,
      builder: (context, _, _) {
        final lists = LookupListService.all()
            .where((l) => query.isEmpty || l.name.toLowerCase().contains(query))
            .toList();
        if (lists.isEmpty && query.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SsIconTile(
                  LucideIcons.listChecks,
                  background: c.emeraldTint,
                  color: c.emerald,
                  size: 56,
                ),
                const SizedBox(height: 16),
                Text(
                  'No lists yet',
                  style: SsText.sans(
                    size: 15,
                    weight: FontWeight.w600,
                    color: c.ink,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Import a staff roster, stock list or asset register '
                  'once. Sheets check each scan against it.',
                  textAlign: TextAlign.center,
                  style: SsText.sans(size: 13, color: c.ink2),
                ),
                const SizedBox(height: 20),
                SsButton(
                  'Add a list',
                  large: false,
                  expand: false,
                  onPressed: () => _add(context),
                ),
              ],
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.only(bottom: 120),
          children: [
            SsListGroup(
              children: [
                for (final list in lists)
                  SsListRow(
                    leading: SsIconTile(
                      list.source.isSheets
                          ? LucideIcons.sheet
                          : LucideIcons.fileSpreadsheet,
                      background: c.emeraldTint,
                      color: c.emerald,
                      size: 40,
                    ),
                    title: list.name,
                    subtitle:
                        '${list.length} entries · ${list.source.label} · '
                        '${relativeTime(list.importedAt)}',
                    trailing: SsIconButton(
                      LucideIcons.ellipsisVertical,
                      onPressed: () => _actions(context, list),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            SsButton.secondary(
              'Add a list',
              icon: LucideIcons.plus,
              large: false,
              onPressed: () => _add(context),
            ),
          ],
        );
      },
    );
  }

  Future<void> _actions(BuildContext context, LookupList list) async {
    final users = ScanSessionService.getAllSessions()
        .where((s) => s.lookupListId == list.id)
        .length;
    final choice = await showSsSheet<String>(
      context,
      builder: (ctx) {
        final c = ctx.ss;
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(list.name, style: SsText.section(color: c.ink)),
              const SizedBox(height: 2),
              Text(
                users == 0
                    ? 'Not used by any sheet'
                    : 'Used by $users ${users == 1 ? 'sheet' : 'sheets'}',
                style: SsText.caption(color: c.muted),
              ),
              const SizedBox(height: 14),
              SsListGroup(
                children: [
                  if (list.source.isSheets)
                    SsListRow(
                      leading: Icon(LucideIcons.refreshCw, color: c.ink),
                      title: 'Refresh from Google Sheets',
                      onTap: () => Navigator.pop(ctx, 'refresh'),
                    ),
                  SsListRow(
                    leading: Icon(LucideIcons.pencil, color: c.ink),
                    title: 'Rename',
                    onTap: () => Navigator.pop(ctx, 'rename'),
                  ),
                  SsListRow(
                    leading: Icon(LucideIcons.trash2, color: c.error),
                    title: 'Delete list',
                    subtitle: users == 0
                        ? null
                        : 'Its sheets keep their rows but stop checking',
                    titleColor: c.error,
                    onTap: () => Navigator.pop(ctx, 'delete'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
    if (!context.mounted) return;
    switch (choice) {
      case 'refresh':
        final updated = await LookupListService.refresh(
          list,
          pro: UsageService.instance.isPro,
        );
        if (updated != null) {
          for (final s in ScanSessionService.getAllSessions()) {
            if (s.lookupListId == list.id && s.teamCode != null) {
              TeamService.instance.pushList(s, updated);
            }
          }
        }
        if (context.mounted) {
          showSsToast(
            context,
            updated == null
                ? 'Couldn’t reach Google Sheets. Kept the last copy.'
                : '${updated.name} updated · ${updated.length} entries',
          );
        }
      case 'rename':
        final name = await showSsTextPrompt(
          context,
          title: 'Rename list',
          label: 'List name',
          initial: list.name,
        );
        if (name != null && name.trim().isNotEmpty) {
          await LookupListService.save(list.copyWith(name: name.trim()));
        }
      case 'delete':
        await LookupListService.delete(list.id);
        if (context.mounted) showSsToast(context, '${list.name} deleted');
    }
  }
}
