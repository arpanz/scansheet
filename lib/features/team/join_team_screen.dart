import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/services/google_sheets_service.dart';
import '../../core/services/team_service.dart';
import '../../core/services/usage_service.dart';
import '../../core/utils/app_router.dart';
import '../../core/widgets/ss.dart';
import '../scan/models/column_kind.dart';
import '../scan/screens/scan_session_screen.dart';

/// "Join a team sheet": scan a teammate's QR or type their code, check the
/// sheet, then scan into it.
class JoinTeamScreen extends StatefulWidget {
  const JoinTeamScreen({super.key});

  @override
  State<JoinTeamScreen> createState() => _JoinTeamScreenState();
}

class _JoinTeamScreenState extends State<JoinTeamScreen> {
  final _code = TextEditingController();
  TeamSheet? _team;
  bool _mine = false;
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _look(String text) async {
    final code = TeamService.codeFrom(text);
    if (code == null) {
      showSsToast(context, 'That isn’t a ScanSheet invite code.');
      return;
    }
    setState(() => _busy = true);
    try {
      if (!GoogleSheetsService.instance.isSignedIn &&
          await GoogleSheetsService.instance.signIn() == null) {
        return;
      }
      final team = await TeamService.instance.fetch(code);
      if (!mounted) return;
      if (team == null || !team.active) {
        showSsToast(
          context,
          team == null
              ? 'No team sheet with code $code.'
              : 'That sheet isn’t shared any more.',
        );
        return;
      }
      final uid = (await UsageService.instance.firebaseUser())?.uid;
      if (!mounted) return;
      setState(() {
        _team = team;
        _mine = team.ownerUid == uid;
      });
    } on TeamException catch (e) {
      if (mounted) showSsToast(context, e.message);
    } catch (e) {
      debugPrint('Join lookup failed: $e');
      if (mounted) {
        showSsToast(context, 'Couldn’t check that code. Are you online?');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _scanQr() async {
    final text = await Navigator.of(
      context,
    ).push<String>(FadeSlideRoute(page: const _QrScanner()));
    if (text == null || !mounted) return;
    _code.text = TeamService.codeFrom(text) ?? text;
    await _look(text);
  }

  Future<void> _join() async {
    final team = _team;
    if (team == null) return;
    setState(() => _busy = true);
    try {
      final session = await TeamService.instance.join(team);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        FadeSlideRoute(page: ScanSessionScreen(session: session)),
      );
    } catch (e) {
      debugPrint('Join failed: $e');
      if (mounted) showSsToast(context, 'Couldn’t join. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    final team = _team;
    return Scaffold(
      backgroundColor: c.paper,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            SsPageHeader(
              title: 'Join a team sheet',
              onBack: () => Navigator.maybePop(context),
            ),
            const SizedBox(height: 12),
            Text(
              'Scan the QR on your teammate’s phone, or type the code '
              'they sent you.',
              style: SsText.body(color: c.ink2),
            ),
            const SizedBox(height: 18),
            SsButton(
              'Scan their QR',
              icon: LucideIcons.qrCode,
              onPressed: _busy ? null : _scanQr,
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 52,
                    child: TextField(
                      controller: _code,
                      textCapitalization: TextCapitalization.characters,
                      autocorrect: false,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'[A-Za-z0-9 ]'),
                        ),
                        LengthLimitingTextInputFormatter(7),
                      ],
                      style: SsText.mono(
                        size: 18,
                        weight: FontWeight.w600,
                        color: c.ink,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Code, like K7Q 2PM',
                        filled: true,
                        fillColor: c.surface,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: c.line, width: 1.5),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: c.ink, width: 1.5),
                        ),
                      ),
                      onSubmitted: _look,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SsButton.secondary(
                  'Check',
                  expand: false,
                  loading: _busy && team == null,
                  onPressed: _busy ? null : () => _look(_code.text),
                ),
              ],
            ),
            if (team != null) ...[
              const SizedBox(height: 20),
              SsCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(team.name, style: SsText.heading(color: c.ink)),
                    const SizedBox(height: 2),
                    Text(
                      'Shared by ${team.ownerName}',
                      style: SsText.caption(color: c.muted),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final col in team.columns)
                          _ColumnChip(name: col.name, kind: ColumnKind.of(col)),
                      ],
                    ),
                    if (team.hasList) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Icon(
                            LucideIcons.listChecks,
                            size: 16,
                            color: c.emerald,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Checks against ${team.listName ?? 'a list'}',
                              style: SsText.caption(color: c.ink2),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _mine
                    ? 'This is your sheet.'
                    : '${team.ownerName}’s phone gives you access to the '
                          'spreadsheet. Until then your rows wait safely on '
                          'this phone.',
                style: SsText.caption(color: c.muted),
              ),
              const SizedBox(height: 18),
              SsButton(
                _mine ? 'Open it' : 'Join and start scanning',
                icon: ssScanIcon,
                loading: _busy,
                onPressed: _join,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ColumnChip extends StatelessWidget {
  final String name;
  final ColumnKind kind;
  const _ColumnChip({required this.name, required this.kind});

  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
      decoration: BoxDecoration(
        color: c.paper,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(name, style: SsText.sans(size: 13, color: c.ink)),
          const SizedBox(width: 6),
          SsTag(kind.tag, kind: kind.tagKind),
        ],
      ),
    );
  }
}

/// Full-screen camera that pops with the first QR it reads.
class _QrScanner extends StatefulWidget {
  const _QrScanner();

  @override
  State<_QrScanner> createState() => _QrScannerState();
}

class _QrScannerState extends State<_QrScanner> {
  final _camera = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );
  bool _done = false;

  @override
  void dispose() {
    _camera.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SsColors.night,
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _camera,
            onDetect: (capture) {
              final value = capture.barcodes.firstOrNull?.rawValue;
              if (_done || value == null) return;
              _done = true;
              HapticFeedback.mediumImpact();
              Navigator.pop(context, value);
            },
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      SsIconButton(
                        LucideIcons.x,
                        color: Colors.white,
                        background: Colors.white.withValues(alpha: .14),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Scan your teammate’s QR',
                        style: SsText.sans(
                          size: 16,
                          weight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ],
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
