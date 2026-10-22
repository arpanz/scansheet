import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/ss.dart';

class ScanHelpScreen extends StatefulWidget {
  final VoidCallback onTryAgain;
  const ScanHelpScreen({super.key, required this.onTryAgain});

  @override
  State<ScanHelpScreen> createState() => _ScanHelpScreenState();
}

class _ScanHelpScreenState extends State<ScanHelpScreen> {
  String _open = 'dark';

  @override
  Widget build(BuildContext context) {
    final tips = <(String, IconData, String, String, String, VoidCallback)>[
      (
        'dark',
        LucideIcons.flashlight,
        'Too dark to read',
        'The torch helps a lot. You can also keep scanning with it on.',
        'Scan with torch on',
        widget.onTryAgain,
      ),
      (
        'noread',
        LucideIcons.scanBarcode,
        'The code won’t read',
        'Worn or tiny codes happen. Type the number instead and it still lands in the same row.',
        'Type the code',
        widget.onTryAgain,
      ),
      (
        'nothing',
        LucideIcons.house,
        'Nothing to scan yet',
        'No problem. Your sheet is saved and waits right on the home screen.',
        'Back to home',
        () => Navigator.of(context).popUntil((r) => r.isFirst),
      ),
      (
        'other',
        LucideIcons.messageSquare,
        'Something else',
        'Tell us in a line. It goes straight to the person who builds ScanSheet.',
        'Send feedback',
        () => showSsToast(context, 'Feedback is coming in the next update'),
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
              for (final tip in tips) ...[
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: _open == tip.$1
                        ? SsColors.nightSurface
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: _open == tip.$1
                          ? SsColors.brandLime
                          : SsColors.nightLine,
                      width: _open == tip.$1 ? 1.5 : 1,
                    ),
                  ),
                  child: Column(
                    children: [
                      ListTile(
                        leading: Icon(
                          tip.$2,
                          color: _open == tip.$1
                              ? SsColors.brandLime
                              : SsColors.nightText,
                        ),
                        title: Text(
                          tip.$3,
                          style: SsText.sans(
                            size: 16,
                            weight: FontWeight.w500,
                            color: Colors.white,
                          ),
                        ),
                        onTap: () => setState(
                          () => _open = _open == tip.$1 ? '' : tip.$1,
                        ),
                      ),
                      if (_open == tip.$1)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(52, 0, 16, 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                tip.$4,
                                style: SsText.sans(
                                  size: 14,
                                  height: 1.45,
                                  color: SsColors.nightText,
                                ),
                              ),
                              const SizedBox(height: 12),
                              FilledButton(
                                onPressed: tip.$6,
                                child: Text(tip.$5),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              const Spacer(),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
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
