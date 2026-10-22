import 'dart:ui';
import 'package:flutter/material.dart';
import '../ads/ad_manager.dart';
import '../theme/tokens.dart';
import 'ss.dart';

class BeautifulLoadingWidget extends StatelessWidget {
  final String message;
  final VoidCallback? onCancel;
  final bool showAd;

  const BeautifulLoadingWidget({
    super.key,
    required this.message,
    this.onCancel,
    this.showAd = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.ss;
    return Stack(
      children: [
        Positioned.fill(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(color: c.ink.withValues(alpha: 0.35)),
          ),
        ),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: SsCard(
                radius: 20,
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 44,
                      height: 44,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        valueColor: AlwaysStoppedAnimation<Color>(c.emerald),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: SsText.label(color: c.ink),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Please wait a moment\u2026',
                      style: SsText.caption(color: c.muted),
                    ),
                    if (showAd && !AdManager.instance.isPro) ...[
                      const SizedBox(height: 24),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: AdManager.instance.getNativeAdWidget(
                          isMedium: true,
                        ),
                      ),
                    ],
                    if (onCancel != null) ...[
                      const SizedBox(height: 24),
                      SsButton(
                        'Cancel',
                        kind: SsButtonKind.ghost,
                        onPressed: onCancel,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
