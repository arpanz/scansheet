import 'package:flutter/material.dart';

import '../../core/services/scan_session_service.dart';
import '../../core/services/sync_queue_service.dart';
import '../../core/widgets/ss.dart';
import '../../core/utils/app_router.dart';
import '../scan/models/scan_session.dart';
import '../scan/screens/done_for_now_screen.dart';
import '../team/team_screen.dart';

/// One place for a sheet's lifecycle: finish, reopen, rename, clear, delete.
/// Used from Sheet view, Library, Home and Done for now.
///
/// "Finish" is the everyday action: the sheet stops being "in progress", so
/// the Scan button no longer jumps into it and it stops counting as an open
/// sheet. Nothing is deleted and it can be reopened from Library anytime.
Future<void> showSheetActions(
  BuildContext context,
  ScanSession session, {
  VoidCallback? onDeleted,
}) async {
  final action = await showSsSheet<_Action>(
    context,
    builder: (ctx) => _ActionsSheet(session: session),
  );
  if (action == null || !context.mounted) return;
  switch (action) {
    case _Action.finish:
      await finishSheet(context, session);
    case _Action.reopen:
      await reopenSheet(context, session);
    case _Action.team:
      await openTeam(context, session);
    case _Action.export:
      await Navigator.of(context).push(
        FadeSlideRoute(
          page: DoneForNowScreen(
            session: session,
            addedThisVisit: 0,
            totalRows: ScanSessionService.getRowCount(session.id),
          ),
        ),
      );
    case _Action.rename:
      await renameSheet(context, session);
    case _Action.clear:
      await clearSheetRows(context, session);
    case _Action.delete:
      if (await deleteSheet(context, session)) onDeleted?.call();
  }
}

Future<void> finishSheet(BuildContext context, ScanSession session) async {
  await ScanSessionService.endSession(session.id);
  if (context.mounted) {
    showSsToast(
      context,
      '“${session.name}” finished · it stays in Library',
      action: 'Undo',
      onAction: () => _setActive(session.id, true),
    );
  }
}

Future<void> reopenSheet(BuildContext context, ScanSession session) async {
  await _setActive(session.id, true);
  if (context.mounted) {
    showSsToast(context, '“${session.name}” is open again');
  }
}

/// Finish every open sheet at once (Library).
Future<void> finishAllSheets(BuildContext context) async {
  final open = ScanSessionService.getAllSessions()
      .where((s) => s.isActive)
      .toList();
  for (final s in open) {
    await ScanSessionService.endSession(s.id);
  }
  if (context.mounted && open.isNotEmpty) {
    showSsToast(
      context,
      open.length == 1 ? '1 sheet finished' : '${open.length} sheets finished',
      action: 'Undo',
      onAction: () async {
        for (final s in open) {
          await _setActive(s.id, true);
        }
      },
    );
  }
}

Future<void> renameSheet(BuildContext context, ScanSession session) async {
  final name = await showSsTextPrompt(
    context,
    title: 'Rename sheet',
    label: 'Sheet name',
    initial: session.name,
  );
  if (name == null || name.trim().isEmpty) return;
  final current = ScanSessionService.getSession(session.id) ?? session;
  await ScanSessionService.saveSession(current.copyWith(name: name.trim()));
}

Future<void> clearSheetRows(BuildContext context, ScanSession session) async {
  final rows = ScanSessionService.getRowCount(session.id);
  if (rows == 0) {
    showSsToast(context, 'This sheet has no rows yet');
    return;
  }
  final isSheets = session.destination == SessionDestination.googleSheets;
  final ok = await _confirm(
    context,
    title: 'Clear $rows ${rows == 1 ? 'row' : 'rows'}?',
    body: isSheets
        ? 'Empties “${session.name}” on this phone so you can start over. '
              'Rows already in Google Sheets stay there.'
        : 'Empties “${session.name}” on this phone so you can start over.',
    action: 'Clear rows',
  );
  if (!ok) return;
  await SyncQueueService.clearForSession(session.id);
  await ScanSessionService.clearRows(session.id);
  if (context.mounted) showSsToast(context, 'Rows cleared');
}

/// Returns true when the sheet was deleted.
Future<bool> deleteSheet(BuildContext context, ScanSession session) async {
  final isSheets = session.destination == SessionDestination.googleSheets;
  final ok = await _confirm(
    context,
    title: 'Delete “${session.name}”?',
    body: isSheets
        ? 'Removes the sheet and its rows from this phone. '
              'The spreadsheet in Google Drive is kept.'
        : 'Removes the sheet and its rows from this phone.',
    action: 'Delete',
  );
  if (!ok) return false;
  await SyncQueueService.clearForSession(session.id);
  await ScanSessionService.deleteSession(session.id);
  return true;
}

Future<void> _setActive(String id, bool active) async {
  final s = ScanSessionService.getSession(id);
  if (s == null) return;
  await ScanSessionService.saveSession(s.copyWith(isActive: active));
}

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String body,
  required String action,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final c = ctx.ss;
      return Dialog(
        backgroundColor: c.paper,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: SsText.heading(color: c.ink)),
              const SizedBox(height: 8),
              Text(body, style: SsText.body(color: c.muted)),
              const SizedBox(height: 20),
              SsButton(
                action,
                kind: SsButtonKind.danger,
                large: false,
                onPressed: () => Navigator.pop(ctx, true),
              ),
              const SizedBox(height: 8),
              SsButton(
                'Cancel',
                kind: SsButtonKind.ghost,
                large: false,
                onPressed: () => Navigator.pop(ctx, false),
              ),
            ],
          ),
        ),
      );
    },
  );
  return ok ?? false;
}

enum _Action { finish, reopen, team, export, rename, clear, delete }

class _ActionsSheet extends StatelessWidget {
  final ScanSession session;
  const _ActionsSheet({required this.session});

  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    final rows = ScanSessionService.getRowCount(session.id);
    void pick(_Action a) => Navigator.pop(context, a);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            session.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: SsText.sans(
              size: 20,
              weight: FontWeight.w600,
              spacing: -0.4,
              color: c.ink,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${session.isActive ? 'In progress' : 'Finished'} · '
            '$rows ${rows == 1 ? 'row' : 'rows'}',
            style: SsText.caption(color: c.muted),
          ),
          const SizedBox(height: 14),
          SsListGroup(
            children: [
              if (session.isActive)
                SsListRow(
                  leading: SsIconTile(LucideIcons.circleCheck, size: 36),
                  title: 'Finish sheet',
                  subtitle: 'Stop resuming it from Scan. Reopen anytime.',
                  onTap: () => pick(_Action.finish),
                )
              else
                SsListRow(
                  leading: SsIconTile(LucideIcons.rotateCcw, size: 36),
                  title: 'Reopen sheet',
                  subtitle: 'Make it the sheet Scan continues',
                  onTap: () => pick(_Action.reopen),
                ),
              if (session.destination == SessionDestination.googleSheets)
                SsListRow(
                  leading: SsIconTile(LucideIcons.users, size: 36),
                  title: session.teamCode == null
                      ? 'Scan together'
                      : 'Team · code ${session.teamCode}',
                  subtitle: session.teamCode == null
                      ? 'Teammates add rows from their phones'
                      : 'Who’s in, invite more, stop sharing',
                  onTap: () => pick(_Action.team),
                ),
              if (session.destination == SessionDestination.googleSheets)
                SsListRow(
                  leading: SsIconTile(LucideIcons.fileDown, size: 36),
                  title: 'Save a file copy',
                  subtitle: 'Excel or CSV, to keep or share',
                  onTap: () => pick(_Action.export),
                ),
              SsListRow(
                leading: SsIconTile(LucideIcons.pencil, size: 36),
                title: 'Rename',
                onTap: () => pick(_Action.rename),
              ),
              SsListRow(
                leading: SsIconTile(LucideIcons.eraser, size: 36),
                title: 'Clear rows',
                subtitle: 'Start over with the same columns',
                onTap: () => pick(_Action.clear),
              ),
              SsListRow(
                leading: SsIconTile(
                  LucideIcons.trash2,
                  size: 36,
                  color: c.error,
                ),
                title: 'Delete sheet',
                titleColor: c.error,
                onTap: () => pick(_Action.delete),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
