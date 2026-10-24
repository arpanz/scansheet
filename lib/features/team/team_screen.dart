import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/services/google_sheets_service.dart';
import '../../core/services/scan_session_service.dart';
import '../../core/services/sheet_summary.dart';
import '../../core/services/team_service.dart';
import '../../core/services/usage_service.dart';
import '../../core/utils/app_router.dart';
import '../../core/widgets/ss.dart';
import '../scan/models/scan_session.dart';
import '../settings/screens/paywall_screen.dart';

/// "Scan together" (ShareSheet.dc.html): the invite QR and link, who's in,
/// and stop sharing. Teammates see the same people and can leave.
class TeamScreen extends StatefulWidget {
  final ScanSession session;
  const TeamScreen({super.key, required this.session});

  @override
  State<TeamScreen> createState() => _TeamScreenState();
}

class _TeamScreenState extends State<TeamScreen> {
  late ScanSession _session = widget.session;
  bool _busy = false;
  String? _uid;

  @override
  void initState() {
    super.initState();
    UsageService.instance.firebaseUser().then((u) {
      if (mounted) setState(() => _uid = u?.uid);
    });
  }

  bool get _canShare {
    final usage = UsageService.instance;
    return usage.isPro || (usage.usage.value?.inTrial ?? false);
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } on TeamException catch (e) {
      if (mounted) showSsToast(context, e.message);
    } catch (e) {
      debugPrint('Team action failed: $e');
      if (mounted) {
        showSsToast(context, 'That didn’t work. Check your connection.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _start() async {
    if (!_canShare) {
      await Navigator.of(
        context,
      ).push(FadeSlideRoute(page: const PaywallScreen()));
      if (!_canShare) return;
    }
    await _run(() async {
      if (!GoogleSheetsService.instance.isSignedIn &&
          await GoogleSheetsService.instance.signIn() == null) {
        return;
      }
      final shared = await TeamService.instance.share(_session);
      final user = await UsageService.instance.firebaseUser();
      if (mounted) {
        setState(() {
          _session = shared;
          _uid = user?.uid;
        });
      }
    });
  }

  Future<void> _invite(String code) => SharePlus.instance.share(
    ShareParams(
      subject: 'Scan with me: ${_session.name}',
      text:
          'Scan with me into “${_session.name}” in ScanSheet.\n'
          'Open ScanSheet › Scan › Join a team sheet and enter $code\n'
          '${TeamService.linkFor(code)}',
    ),
  );

  Future<void> _stop() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Stop sharing?'),
        content: const Text(
          'Teammates keep the rows on their phones but can’t add to this '
          'spreadsheet any more.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Stop sharing'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() async {
      await TeamService.instance.stopSharing(_session);
      if (mounted) Navigator.pop(context);
    });
  }

  Future<void> _leave() => _run(() async {
    await TeamService.instance.leave(_session);
    if (mounted) {
      showSsToast(context, 'You left. Your rows stay on this phone.');
      Navigator.pop(context);
    }
  });

  Future<void> _memberActions(TeamSheet team, TeamMember member) async {
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
              Text(member.name, style: SsText.section(color: c.ink)),
              Text(member.email, style: SsText.caption(color: c.muted)),
              const SizedBox(height: 14),
              SsListGroup(
                children: [
                  if (member.access != 'granted')
                    SsListRow(
                      leading: Icon(LucideIcons.keyRound, color: c.ink),
                      title: 'Give access again',
                      onTap: () => Navigator.pop(ctx, 'grant'),
                    ),
                  SsListRow(
                    leading: Icon(LucideIcons.userX, color: c.error),
                    title: 'Remove from sheet',
                    subtitle: 'Their rows already in the sheet stay',
                    titleColor: c.error,
                    onTap: () => Navigator.pop(ctx, 'remove'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
    switch (choice) {
      case 'grant':
        await _run(() => TeamService.instance.grantAccess(team, member));
      case 'remove':
        await _run(() => TeamService.instance.removeMember(team, member));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    final code = _session.teamCode;
    return Scaffold(
      backgroundColor: c.paper,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SsPageHeader(
                title: 'Scan together',
                onBack: () => Navigator.maybePop(context),
              ),
              Expanded(
                child: code == null
                    ? _intro(c)
                    : StreamBuilder<TeamSheet?>(
                        stream: TeamService.instance.watch(code),
                        builder: (context, snap) {
                          final team = snap.data;
                          if (snap.hasError) {
                            return Center(
                              child: Text(
                                'Couldn’t load the team. Check your connection.',
                                textAlign: TextAlign.center,
                                style: SsText.body(color: c.muted),
                              ),
                            );
                          }
                          if (team == null) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }
                          return _shared(c, team);
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _intro(SsColors c) {
    final sheets = _session.destination == SessionDestination.googleSheets;
    return ListView(
      padding: const EdgeInsets.only(top: 12, bottom: 24),
      children: [
        Text(_session.name, style: SsText.title(color: c.ink)),
        const SizedBox(height: 8),
        Text(
          sheets
              ? 'Teammates scan this in ScanSheet and their rows land in the '
                    'same Google Sheet, with the same columns'
                    '${_session.lookupListId == null ? '' : ' and list'}.'
              : 'Scanning together works with Google Sheets. Make a new '
                    'sheet that saves to Google Sheets to share it.',
          style: SsText.body(color: c.ink2),
        ),
        const SizedBox(height: 20),
        SsListGroup(
          children: [
            SsListRow(
              leading: SsIconTile(LucideIcons.qrCode, size: 36),
              title: 'They scan your QR or enter a code',
              subtitle: 'From Scan › Join a team sheet',
            ),
            SsListRow(
              leading: SsIconTile(LucideIcons.keyRound, size: 36),
              title: 'ScanSheet gives them access',
              subtitle: 'To this spreadsheet only, while you share it',
            ),
            SsListRow(
              leading: SsIconTile(LucideIcons.users, size: 36),
              title: 'See who’s scanning',
              subtitle: 'And how many rows each person added',
            ),
          ],
        ),
        const SizedBox(height: 24),
        if (sheets)
          SsButton(
            _canShare ? 'Start sharing' : 'Start sharing · Pro',
            icon: LucideIcons.users,
            loading: _busy,
            onPressed: _start,
          ),
      ],
    );
  }

  Widget _shared(SsColors c, TeamSheet team) {
    final owner = team.ownerUid == _uid;
    if (!team.active) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${team.ownerName} stopped sharing “${team.name}”.',
                textAlign: TextAlign.center,
                style: SsText.body(color: c.ink2),
              ),
              const SizedBox(height: 16),
              SsButton(
                'OK, keep my rows here',
                large: false,
                loading: _busy,
                onPressed: _leave,
              ),
            ],
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.only(top: 12, bottom: 24),
      children: [
        Text(team.name, style: SsText.title(color: c.ink)),
        const SizedBox(height: 6),
        Text(
          'Teammates scan this in ScanSheet and their rows land in the same '
          'Google Sheet, with the same columns.',
          style: SsText.body(color: c.ink2),
        ),
        const SizedBox(height: 18),
        SsCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: QrImageView(
                  data: TeamService.linkFor(team.code),
                  size: 168,
                  padding: EdgeInsets.zero,
                ),
              ),
              const SizedBox(height: 12),
              SelectableText(
                '${team.code.substring(0, 3)} ${team.code.substring(3)}',
                style: SsText.mono(
                  size: 24,
                  weight: FontWeight.w600,
                  color: c.ink,
                ),
              ),
              Text(
                'Scan › Join a team sheet',
                style: SsText.caption(color: c.muted),
              ),
              const SizedBox(height: 14),
              SsButton.secondary(
                'Share invite link',
                icon: LucideIcons.share2,
                onPressed: () => _invite(team.code),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        StreamBuilder<List<TeamMember>>(
          stream: TeamService.instance.members(team.code),
          builder: (context, snap) {
            final members = snap.data ?? const <TeamMember>[];
            final now = DateTime.now();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'People · ${members.length}',
                  style: SsText.sans(
                    size: 13,
                    weight: FontWeight.w500,
                    color: c.ink2,
                  ),
                ),
                const SizedBox(height: 8),
                SsListGroup(
                  children: [
                    for (final m in members)
                      SsListRow(
                        leading: SsAvatar(
                          initial: (m.name.isEmpty ? m.email : m.name)
                              .substring(0, 1)
                              .toUpperCase(),
                        ),
                        title: m.uid == _uid ? 'You' : m.name,
                        subtitle: _status(m, now),
                        trailing: m.scanningAt(now)
                            ? SsDot(color: c.emerald, size: 8)
                            : null,
                        onTap: owner && !m.isOwner
                            ? () => _memberActions(team, m)
                            : null,
                      ),
                  ],
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 20),
        SsButton(
          owner ? 'Stop sharing' : 'Leave team sheet',
          kind: SsButtonKind.ghost,
          large: false,
          loading: _busy,
          onPressed: owner ? _stop : _leave,
        ),
      ],
    );
  }

  String _status(TeamMember m, DateTime now) {
    final rows = '${m.rows} ${m.rows == 1 ? 'row' : 'rows'}';
    if (m.access == 'requested') return 'Joined · waiting for access';
    if (m.access == 'failed') {
      return 'Couldn’t share the spreadsheet. Share it with ${m.email} '
          'in Google Sheets.';
    }
    if (m.scanningAt(now)) return 'Scanning now · $rows';
    final seen = m.lastSeen;
    return [
      if (m.isOwner) 'Owner',
      rows,
      if (seen != null && !m.isOwner)
        'seen ${relativeTime(seen).toLowerCase()}',
    ].join(' · ');
  }
}

/// Opens Scan together for [session], re-read so a fresh share shows.
Future<void> openTeam(BuildContext context, ScanSession session) =>
    Navigator.of(context).push(
      FadeSlideRoute(
        page: TeamScreen(
          session: ScanSessionService.getSession(session.id) ?? session,
        ),
      ),
    );
