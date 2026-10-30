import 'package:flutter/material.dart';

import '../../core/ads/ad_manager.dart';
import '../../core/services/usage_service.dart';
import '../../core/utils/app_router.dart';
import '../../core/widgets/ss.dart';
import '../settings/screens/paywall_screen.dart';

void openPaywall(BuildContext context) =>
    Navigator.of(context).push(FadeSlideRoute(page: const PaywallScreen()));

/// "37 of 200 rows this month" with a thin bar. Hidden for Pro.
class UsageMeter extends StatelessWidget {
  const UsageMeter({super.key});

  @override
  Widget build(BuildContext context) {
    final usage = UsageService.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([
        usage.usage,
        AdManager.instance.isProNotifier,
      ]),
      builder: (context, _) {
        final text = usage.summary;
        if (text == null) return const SizedBox.shrink();
        final c = context.ss;
        final used = (usage.usage.value.rowsThisMonth / Usage.monthlyRows)
            .clamp(0.0, 1.0);
        final tone = usage.rowsLeft == 0
            ? c.error
            : usage.nearLimit
            ? c.amber
            : c.emerald;
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: SsCard(
            radius: 16,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            onTap: () => openPaywall(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        text,
                        style: SsText.sans(
                          size: 13,
                          weight: FontWeight.w600,
                          color: c.ink,
                        ),
                      ),
                    ),
                    Text('Free plan', style: SsText.caption(color: c.muted)),
                    const SizedBox(width: 4),
                    Icon(LucideIcons.chevronRight, size: 14, color: c.muted),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: used,
                    minHeight: 4,
                    color: tone,
                    backgroundColor: c.chip,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The month's rows are used up. Scanning carries on; new rows wait on the
/// phone, out of Google Sheets and exports, until the 1st or an upgrade.
class LimitReachedCard extends StatelessWidget {
  final int waiting;
  const LimitReachedCard({super.key, required this.waiting});

  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    final now = DateTime.now();
    final first = DateTime(now.year, now.month + 1);
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return SsCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(LucideIcons.gauge, size: 18, color: c.amber),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'You’ve used this month’s ${Usage.monthlyRows} rows',
                      style: SsText.label(color: c.ink),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Keep scanning — $waiting new ${waiting == 1 ? 'row is' : 'rows are'} saved on this phone. They join your sheet and exports on ${first.day} ${months[first.month - 1]}, or right away with Pro.',
                      style: SsText.sans(size: 13, color: c.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SsButton(
            'Unlock every row with Pro',
            large: false,
            onPressed: () => openPaywall(context),
          ),
        ],
      ),
    );
  }
}

/// [proceed]: carry on with Google Sheets (Pro unlocked it).
enum OpenSheetChoice { proceed, keepOnPhone, cancel }

/// Free plan allows [Usage.openSheets] Google Sheets sheets at once.
/// Returns how to continue; the paywall opens from here for "Go Pro".
Future<OpenSheetChoice> showOpenSheetsLimit(BuildContext context) async {
  final navigator = Navigator.of(context);
  final choice = await showSsSheet<_LimitAction>(
    context,
    builder: (ctx) {
      final c = ctx.ss;
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${Usage.openSheets} sheets are already open',
              style: SsText.sans(
                size: 20,
                weight: FontWeight.w600,
                spacing: -0.4,
                color: c.ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'The free plan syncs ${Usage.openSheets} Google Sheets at a time. '
              'Close one in Library, keep this one on the phone, or go Pro '
              'for unlimited sheets.',
              style: SsText.body(color: c.muted),
            ),
            const SizedBox(height: 18),
            SsButton(
              'Go Pro',
              icon: LucideIcons.star,
              onPressed: () => Navigator.pop(ctx, _LimitAction.pro),
            ),
            const SizedBox(height: 8),
            SsButton.secondary(
              'Save as Excel on this phone',
              onPressed: () => Navigator.pop(ctx, _LimitAction.phone),
            ),
          ],
        ),
      );
    },
  );
  switch (choice) {
    case _LimitAction.phone:
      return OpenSheetChoice.keepOnPhone;
    case _LimitAction.pro:
      await navigator.push(FadeSlideRoute(page: const PaywallScreen()));
      return UsageService.instance.canOpenSheet()
          ? OpenSheetChoice.proceed
          : OpenSheetChoice.cancel;
    case null:
      return OpenSheetChoice.cancel;
  }
}

enum _LimitAction { pro, phone }
