import 'package:flutter/material.dart';
import '../ads/ad_manager.dart';

class ProCrownIcon extends StatelessWidget {
  const ProCrownIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AdManager.instance.isProNotifier,
      builder: (context, isPro, _) {
        return IconButton(
          icon: Icon(
            isPro
                ? Icons.workspace_premium_rounded
                : Icons.workspace_premium_outlined,
            color: isPro ? const Color(0xFFFFD700) : null, // Gold if Pro
          ),
          onPressed: () => AdManager.onShowPaywall?.call(context),
          tooltip: isPro ? 'You are a Pro user' : 'Upgrade to Pro',
        );
      },
    );
  }
}
