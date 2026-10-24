import 'package:flutter/material.dart';

import '../../core/models/sync_queue_item.dart';
import '../../core/services/google_sheets_service.dart';
import '../../core/services/scan_session_service.dart';
import '../../core/services/sheets_sync_service.dart';
import '../../core/services/sync_queue_service.dart';
import '../../core/services/usage_service.dart';
import '../../core/utils/app_router.dart';
import '../../core/widgets/ss.dart';
import '../scan/models/scan_session.dart';
import '../settings/screens/connect_sheets_screen.dart';
import 'plan_limits.dart';

/// The one sync problem worth showing right now, most urgent first
/// (docs/design/mocks/States.dc.html). Rows are never lost: every state
/// says they are safe on the phone and offers the next step.
class SyncBanner extends StatelessWidget {
  /// Limit to one sheet (Sheet view); null = all sheets (Home).
  final ScanSession? session;
  const SyncBanner({super.key, this.session});

  @override
  Widget build(BuildContext context) {
    final sync = SheetsSyncService.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([
        SyncQueueService.stats,
        sync.online,
        sync.authExpired,
        sync.missingSheets,
        GoogleSheetsService.instance.signedInNotifier,
        UsageService.instance.syncPaused,
      ]),
      builder: (context, _) {
        final items = SyncQueueService.getAll().where(
          (i) =>
              i.status != SyncStatus.synced &&
              (session == null || i.sessionId == session!.id),
        );
        final waiting = items.length;
        if (waiting == 0) return const SizedBox.shrink();

        final missing = sync.missingSheets.value;
        final lost = ScanSessionService.getAllSessions().where(
          (s) =>
              (session == null || s.id == session!.id) &&
              s.spreadsheetId != null &&
              missing.contains(s.spreadsheetId),
        );
        final Widget child;
        if (lost.isNotEmpty) {
          child = _SheetGone(session: lost.first);
        } else if (UsageService.instance.syncPaused.value &&
            GoogleSheetsService.instance.isSignedIn) {
          child = LimitReachedCard(waiting: waiting);
        } else if (sync.authExpired.value ||
            !GoogleSheetsService.instance.isSignedIn) {
          child = _Reconnect(waiting: waiting);
        } else if (!sync.online.value) {
          child = _Offline(waiting: waiting);
        } else {
          final failed = items
              .where((i) => i.status == SyncStatus.failed)
              .length;
          if (failed == 0) return const SizedBox.shrink();
          child = _Failed(failed: failed);
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: child,
        );
      },
    );
  }
}

class _Offline extends StatelessWidget {
  final int waiting;
  const _Offline({required this.waiting});

  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: c.chip,
        borderRadius: BorderRadius.circular(SsRadius.md),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.wifiOff, size: 16, color: c.ink2),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: SsText.sans(size: 13, color: c.ink2),
                children: [
                  const TextSpan(text: 'No signal. Keep scanning — '),
                  TextSpan(
                    text: '$waiting',
                    style: SsText.mono(size: 13, color: c.ink),
                  ),
                  TextSpan(
                    text: waiting == 1
                        ? ' row will sync later.'
                        : ' rows will sync later.',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Card shell shared by the actionable states.
class _StateCard extends StatelessWidget {
  final IconData icon;
  final Color tone;
  final String title;
  final String body;
  final List<Widget> actions;

  const _StateCard({
    required this.icon,
    required this.tone,
    required this.title,
    required this.body,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    return SsCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: tone),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: SsText.label(color: c.ink)),
                    const SizedBox(height: 2),
                    Text(body, style: SsText.sans(size: 13, color: c.muted)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (var i = 0; i < actions.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(child: actions[i]),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _Failed extends StatelessWidget {
  final int failed;
  const _Failed({required this.failed});

  @override
  Widget build(BuildContext context) {
    final sync = SheetsSyncService.instance;
    return _StateCard(
      icon: LucideIcons.cloudAlert,
      tone: context.ss.error,
      title: failed == 1
          ? '1 row didn’t reach Google Sheets'
          : '$failed rows didn’t reach Google Sheets',
      body: 'They’re safe on this phone. We’ll keep trying in the background.',
      actions: [
        SsButton('Try now', large: false, onPressed: sync.retryNow),
        SsButton.secondary(
          'Details',
          onPressed: () => showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Sync error'),
              content: Text(sync.lastError.value ?? 'Unknown error'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('OK'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Reconnect extends StatelessWidget {
  final int waiting;
  const _Reconnect({required this.waiting});

  @override
  Widget build(BuildContext context) {
    return _StateCard(
      icon: LucideIcons.userRoundX,
      tone: context.ss.amber,
      title: 'Reconnect Google to keep syncing',
      body:
          'Google signed ScanSheet out. Your $waiting new ${waiting == 1 ? 'row is' : 'rows are'} waiting here.',
      actions: [
        SsButton(
          'Reconnect',
          icon: LucideIcons.logIn,
          large: false,
          onPressed: () async {
            try {
              await GoogleSheetsService.instance.signIn();
            } catch (_) {
              if (context.mounted) {
                showSsToast(context, 'Couldn’t sign in. Try again.');
              }
            }
          },
        ),
      ],
    );
  }
}

class _SheetGone extends StatefulWidget {
  final ScanSession session;
  const _SheetGone({required this.session});

  @override
  State<_SheetGone> createState() => _SheetGoneState();
}

class _SheetGoneState extends State<_SheetGone> {
  bool _busy = false;

  ScanSession get _s => widget.session;

  List<(int, List<String>)> get _rows => [
    for (final r in ScanSessionService.getRows(_s.id))
      (r.rowIndex, _s.cellsFor(r)),
  ];

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (_) {
      if (mounted) showSsToast(context, 'That didn’t work. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _moveTo(String spreadsheetId, String? sheetName) async {
    final old = _s.spreadsheetId!;
    await ScanSessionService.saveSession(
      _s.copyWith(spreadsheetId: spreadsheetId, sheetName: sheetName),
    );
    await SyncQueueService.resendSession(
      _s.id,
      spreadsheetId,
      sheetName,
      _rows,
    );
    SheetsSyncService.instance.forgetMissing(old);
    SheetsSyncService.instance.syncSoon();
  }

  Future<void> _newSheet() => _run(() async {
    final id = await GoogleSheetsService.instance.createSpreadsheet(_s.name);
    await _moveTo(id, null);
  });

  Future<void> _pickAnother() => _run(() async {
    final dest = await Navigator.of(
      context,
    ).push<SheetDestination>(FadeSlideRoute(page: const ConnectSheetsScreen()));
    if (dest != null) await _moveTo(dest.spreadsheetId, dest.sheetName);
  });

  Future<void> _keepLocal() => _run(() async {
    final old = _s.spreadsheetId!;
    await ScanSessionService.saveSession(
      _s.copyWith(destination: SessionDestination.localXlsx),
    );
    await SyncQueueService.clearForSession(_s.id);
    SheetsSyncService.instance.forgetMissing(old);
  });

  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    return SsCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(LucideIcons.fileX, size: 18, color: c.error),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Sheet no longer available',
                  style: SsText.label(color: c.ink),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.only(left: 28),
            child: Text(
              '“${_s.name}” was deleted or you lost access.',
              style: SsText.sans(size: 13, color: c.muted),
            ),
          ),
          const SizedBox(height: 12),
          SsButton(
            'Send rows to a new sheet',
            large: false,
            loading: _busy,
            onPressed: _newSheet,
          ),
          const SizedBox(height: 8),
          SsButton.secondary(
            'Pick another spreadsheet',
            onPressed: _busy ? null : _pickAnother,
          ),
          const SizedBox(height: 8),
          SsButton.secondary(
            'Save as Excel on this phone',
            onPressed: _busy ? null : _keepLocal,
          ),
        ],
      ),
    );
  }
}
