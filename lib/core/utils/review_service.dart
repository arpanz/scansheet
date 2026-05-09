import 'package:scansheet/core/theme/app_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class ReviewService {
  static const String _androidPackageName = 'com.livinlabs.batchqr';
  static const String? _iosAppStoreId = null;
  static const String _kActiveDaysKey = 'active_use_days';
  static const String _kLastActiveDateKey = 'last_active_date';
  // true = never ask again
  static const String _kReviewCompletedKey = 'review_completed';
  // ms since epoch, don't ask before this
  static const String _kCooldownUntilKey = 'review_cooldown_until';

  static bool _sessionPrompted = false;

  static bool get _isApplePlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  static Future<void> openStoreListing(BuildContext context) async {
    final inAppReview = InAppReview.instance;

    try {
      await inAppReview.openStoreListing(appStoreId: _iosAppStoreId);
      return;
    } catch (_) {
      if (_isApplePlatform && _iosAppStoreId == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'App Store review link is not configured for this build yet.',
              ),
            ),
          );
        }
        return;
      }
    }

    final opened = await launchUrl(
      Uri.parse(
        'https://play.google.com/store/apps/details?id=$_androidPackageName',
      ),
      mode: LaunchMode.externalApplication,
    );

    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the store listing.')),
      );
    }
  }

  /// Temporary/manual trigger for UI verification from Settings.
  /// Shows the same custom dialogs without touching review gating state.
  static Future<void> showDebugReviewPrompt(BuildContext context) async {
    try {
      if (!context.mounted) return;
      final result = await _showPreAskDialog(context);
      if (result == false && context.mounted) {
        _showFeedbackRedirect(context);
      }
    } catch (_) {
      // Fail silently
    }
  }

  /// Call this on app initialization to track active days.
  static Future<void> trackDailyLaunch() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();
      final todayStr = '${now.year}-${now.month}-${now.day}';

      final lastActiveDate = prefs.getString(_kLastActiveDateKey);

      if (lastActiveDate != todayStr) {
        final activeDays = (prefs.getInt(_kActiveDaysKey) ?? 0) + 1;
        await prefs.setInt(_kActiveDaysKey, activeDays);
        await prefs.setString(_kLastActiveDateKey, todayStr);
      }
    } catch (_) {
      // Fail silently
    }
  }

  /// Inject at success moments (e.g., successful file save/export).
  static Future<void> triggerSuccessReview(BuildContext context) async {
    try {
      if (_sessionPrompted) return;

      final prefs = await SharedPreferences.getInstance();

      final reviewCompleted = prefs.getBool(_kReviewCompletedKey) ?? false;
      if (reviewCompleted) {
        _sessionPrompted = true;
        return;
      }

      final cooldownUntil = prefs.getInt(_kCooldownUntilKey) ?? 0;
      if (cooldownUntil > 0 &&
          DateTime.now().millisecondsSinceEpoch < cooldownUntil) {
        _sessionPrompted = true;
        return;
      }

      final activeDays = prefs.getInt(_kActiveDaysKey) ?? 0;
      if (activeDays < 3) return;

      final inAppReview = InAppReview.instance;
      if (!await inAppReview.isAvailable()) return;
      if (!context.mounted) return;

      final result = await _showPreAskDialog(context);

      if (result == null) {
        final blockUntil = DateTime.now()
            .add(const Duration(days: 15))
            .millisecondsSinceEpoch;
        await prefs.setInt(_kCooldownUntilKey, blockUntil);
        _sessionPrompted = true;
        return;
      }

      _sessionPrompted = true;

      if (result == true) {
        await prefs.setBool(_kReviewCompletedKey, true);
        await inAppReview.requestReview();

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              duration: const Duration(seconds: 6),
              content: const Text('Thanks for rating ScanSheet!'),
              action: SnackBarAction(
                label: 'Rate on Play Store',
                onPressed: () {
                  openStoreListing(context);
                },
              ),
            ),
          );
        }
      } else {
        final blockUntil = DateTime.now()
            .add(const Duration(days: 30))
            .millisecondsSinceEpoch;
        await prefs.setInt(_kCooldownUntilKey, blockUntil);
        if (context.mounted) {
          _showFeedbackRedirect(context);
        }
      }
    } catch (_) {
      // Fail silently
    }
  }

  static void _showFeedbackRedirect(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: 0,
        backgroundColor: ctx.themeSurface,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(ctx).colorScheme.errorContainer
                      .withValues(alpha: 0.7),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.sentiment_dissatisfied_rounded,
                  size: 30,
                  color: ctx.themeError,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'We are sorry to hear that',
                textAlign: TextAlign.center,
                style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Help us improve ScanSheet with one quick suggestion.',
                textAlign: TextAlign.center,
                style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                  color: ctx.themeTextSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton.icon(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      final emailUri = Uri.parse(
                        'mailto:connect.livinlabs@gmail.com?subject=Batch%20QR%20Feedback&body=Hi%2C%20here%27s%20how%20Batch%20QR%20could%20improve%3A%0A%0A',
                      );
                      try {
                        await launchUrl(emailUri);
                      } catch (_) {
                        // Use outer `context` here — `ctx` is already popped.
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              content: const Text(
                                'Could not open email. Please reach us at connect.livinlabs@gmail.com',
                              ),
                            ),
                          );
                        }
                      }
                    },
                    icon: const Icon(Icons.rate_review_rounded, size: 20),
                    label: const Text('Share Feedback'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'Maybe later',
                      style: TextStyle(
                        color: ctx.themeTextSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Future<bool?> _showPreAskDialog(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: 0,
        backgroundColor: ctx.themeSurface,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  // Fixed: was Theme.of(ctx).themeAccentContainer which is a
                  // BuildContext extension, not a ThemeData property — compile error.
                  color: ctx.themeAccentContainer.withValues(alpha: 0.7),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.qr_code_2_rounded,
                  size: 30,
                  color: ctx.themeAccent,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Enjoying ScanSheet?',
                textAlign: TextAlign.center,
                style: Theme.of(ctx).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'If it has been useful, a quick rating helps us improve and grow.',
                textAlign: TextAlign.center,
                style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                  color: ctx.themeTextSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        side: BorderSide(color: ctx.themeBorder),
                      ),
                      child: Text(
                        'Needs work',
                        style: TextStyle(
                          color: ctx.themeTextPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Rate it',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
