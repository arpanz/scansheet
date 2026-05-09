import 'dart:ui';
import 'package:flutter/material.dart';
import '../ads/ad_manager.dart';
import '../theme/app_theme.dart';

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
    return Stack(
      children: [
        Positioned.fill(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              color: context.themeBg.withValues(alpha: 0.5),
            ),
          ),
        ),
        Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 320),
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
            decoration: BoxDecoration(
              color: context.themeCard,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: context.themeBorder.withValues(alpha: 0.4),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 40,
                  offset: const Offset(0, 16),
                  spreadRadius: -8,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 44,
                  height: 44,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    backgroundColor: context.themeBorder,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      context.themeAccent,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: context.themeTextPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Please wait a moment\u2026',
                  style: TextStyle(
                    color: context.themeTextSecondary,
                    fontSize: 13,
                  ),
                ),
                if (showAd && !AdManager.instance.isPro) ...[
                  const SizedBox(height: 24),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: AdManager.instance.getNativeAdWidget(isMedium: true),
                  ),
                ],
                if (onCancel != null) ...[
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: onCancel,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: context.themeTextSecondary,
                        side: BorderSide(
                          color: context.themeBorder.withValues(alpha: 0.5),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
