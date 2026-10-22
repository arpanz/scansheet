import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/ss.dart';

/// What the scanner should do after the "No scan this time" screen.
enum ScanHelpChoice {
  /// Back to the camera with the torch on.
  torch,

  /// Open the type-a-code sheet.
  type,

  /// Leave the scanner; the sheet waits on Home.
  home,

  /// Leave the scanner without anything else.
  close,
}

/// Shown when the scanner is closed before any row was added
/// (docs/design/mocks/ScanHelp.dc.html). Pops with a [ScanHelpChoice];
/// the X returns null, which means "back to the scanner".
class ScanHelpScreen extends StatefulWidget {
  const ScanHelpScreen({super.key});

  @override
  State<ScanHelpScreen> createState() => _ScanHelpScreenState();
}

class _Tip {
  final String id;
  final IconData icon;
  final String title;
  final String body;
  final String action;
  final VoidCallback onAction;
  const _Tip(
    this.id,
    this.icon,
    this.title,
    this.body,
    this.action,
    this.onAction,
  );
}

class _ScanHelpScreenState extends State<ScanHelpScreen> {
  String _open = 'dark';

  void _choose(ScanHelpChoice choice) => Navigator.pop(context, choice);

  Future<void> _feedback() async {
    final uri = Uri.parse(
      'mailto:support@livinlabs.dev?subject=ScanSheet%20scanning%20feedback',
    );
    final ok = await launchUrl(uri);
    if (!ok && mounted) {
      showSsToast(
        context,
        'No email app found. Write to support@livinlabs.dev',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tips = [
      _Tip(
        'dark',
        LucideIcons.flashlight,
        'Too dark to read',
        'The torch helps a lot. You can also keep scanning with it on.',
        'Scan with torch on',
        () => _choose(ScanHelpChoice.torch),
      ),
      _Tip(
        'noread',
        LucideIcons.scanBarcode,
        'The code won’t read',
        'Worn or tiny codes happen. Type the number instead and it still '
            'lands in the same row.',
        'Type the code',
        () => _choose(ScanHelpChoice.type),
      ),
      _Tip(
        'nothing',
        LucideIcons.house,
        'Nothing to scan yet',
        'No problem. Your sheet is saved and waits right on the home screen.',
        'Back to home',
        () => _choose(ScanHelpChoice.home),
      ),
      _Tip(
        'other',
        LucideIcons.messageSquare,
        'Something else',
        'Tell us in a line. It goes straight to the person who builds '
            'ScanSheet.',
        'Send feedback',
        _feedback,
      ),
    ];
    return Scaffold(
      backgroundColor: SsColors.night,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  tooltip: 'Back to the scanner',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(LucideIcons.x, color: Colors.white),
                ),
              ),
              const SizedBox(height: 28),
              Text(
                'No scan this time.\nAnything in the way?',
                style: SsText.title(color: Colors.white),
              ),
              const SizedBox(height: 10),
              Text(
                'Pick one and we’ll help you fix it.',
                style: SsText.body(color: SsColors.nightMuted),
              ),
              const SizedBox(height: 28),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    for (final tip in tips)
                      _TipCard(
                        tip: tip,
                        open: _open == tip.id,
                        onToggle: () => setState(
                          () => _open = _open == tip.id ? '' : tip.id,
                        ),
                      ),
                  ],
                ),
              ),
              Center(
                child: TextButton(
                  onPressed: () => _choose(ScanHelpChoice.close),
                  child: Text(
                    'Nothing’s wrong, just closing',
                    style: SsText.sans(
                      size: 15,
                      weight: FontWeight.w500,
                      color: SsColors.nightText,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TipCard extends StatelessWidget {
  final _Tip tip;
  final bool open;
  final VoidCallback onToggle;
  const _TipCard({
    required this.tip,
    required this.open,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: open ? SsColors.nightSurface : Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: open ? SsColors.brandLime : SsColors.nightLine,
          width: open ? 1.5 : 1,
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      tip.icon,
                      size: 20,
                      color: open ? SsColors.brandLime : SsColors.nightText,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        tip.title,
                        style: SsText.sans(
                          size: 16,
                          weight: FontWeight.w500,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    Icon(
                      open ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                      size: 18,
                      color: SsColors.nightMuted,
                    ),
                  ],
                ),
                if (open)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(36, 10, 0, 2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tip.body,
                          style: SsText.sans(
                            size: 14,
                            height: 1.45,
                            color: SsColors.nightText,
                          ),
                        ),
                        const SizedBox(height: 14),
                        SsButton.lime(
                          tip.action,
                          large: false,
                          expand: false,
                          onPressed: tip.onAction,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
