import 'package:flutter/material.dart';
import '../../../core/services/google_sheets_service.dart';
import '../../../core/widgets/ss.dart';
import '../onboarding_flow.dart';

class OnbSigninStep extends StatefulWidget {
  final OnbStateScope scope;
  const OnbSigninStep({super.key, required this.scope});
  @override
  State<OnbSigninStep> createState() => _OnbSigninStepState();
}

class _OnbSigninStepState extends State<OnbSigninStep> {
  bool _loading = false;
  Future<void> _signIn() async {
    setState(() => _loading = true);
    try {
      final account = await GoogleSheetsService.instance.signIn();
      if (!mounted) return;
      if (account == null) {
        showSsToast(context, 'Sign-in was cancelled');
        return;
      }
      if (widget.scope.state.signinFromNew) {
        widget.scope.goTo(context, OnbStep.camera);
      } else {
        widget.scope.goTo(context, OnbStep.destination);
      }
    } catch (_) {
      if (mounted) {
        showSsToast(context, 'Could not connect to Google. Try again.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    // Scrolls on short phones; on tall ones the Spacer still pins the
    // buttons to the bottom.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: IntrinsicHeight(child: _body(c)),
        ),
      ),
    );
  }

  Widget _body(SsColors c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 22),
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    color: c.ink,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Icon(ssScanIcon, size: 38, color: SsColors.brandLime),
                ),
                const SizedBox(width: 48),
                Icon(LucideIcons.arrowRight, color: c.emerald),
                const SizedBox(width: 48),
                Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: c.line),
                  ),
                  child: Icon(LucideIcons.table2, size: 36, color: c.emerald),
                ),
              ],
            ),
          ),
          const SizedBox(height: 30),
          Text(
            'Connect Google to\nsend rows to Sheets',
            textAlign: TextAlign.center,
            style: SsText.title(color: c.ink),
          ),
          const SizedBox(height: 10),
          Text(
            'Sign in once and your scans flow straight into Google Sheets.',
            textAlign: TextAlign.center,
            style: SsText.body(color: c.ink2),
          ),
          const SizedBox(height: 24),
          Text(
            'Next, Google will ask you this:',
            style: SsText.sans(
              size: 13,
              weight: FontWeight.w500,
              color: c.ink2,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: c.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Select what ScanSheet can access',
                  style: SsText.caption(color: c.ink2),
                ),
                // Google's own wording for the scopes in
                // GoogleSheetsService._scopes, so the real screen matches.
                _ConsentRow(
                  'See, edit, create, and delete all your Google Sheets spreadsheets',
                  why: 'To make your sheet and add each row',
                ),
                _ConsentRow(
                  'See, edit, create, and delete only the specific Google Drive files you use with this app',
                  why: 'To list the sheets you use here and share them',
                ),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: c.limeRow,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Keep both ticked so your rows can reach your sheet',
                    style: SsText.caption(color: c.ink),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '🔒  ScanSheet only opens and writes to the sheets you choose.',
            style: SsText.caption(color: c.ink2),
          ),
          const SizedBox(height: 16),
          const Spacer(),
          SsButton.secondary(
            'Continue with Google',
            icon: LucideIcons.logIn,
            loading: _loading,
            onPressed: _loading ? null : _signIn,
          ),
          const SizedBox(height: 4),
          TextButton(
            onPressed: widget.scope.removeSigninAndGoCamera,
            child: Text(
              'Save on this phone instead',
              style: SsText.sans(
                size: 15,
                weight: FontWeight.w500,
                color: c.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConsentRow extends StatelessWidget {
  final String text;
  final String why;
  const _ConsentRow(this.text, {required this.why});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 9),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                text,
                style: SsText.sans(
                  size: 14,
                  height: 1.4,
                  color: context.ss.ink,
                ),
              ),
              const SizedBox(height: 2),
              Text(why, style: SsText.caption(color: context.ss.ink2)),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Icon(LucideIcons.check, color: context.ss.emerald, size: 20),
      ],
    ),
  );
}
