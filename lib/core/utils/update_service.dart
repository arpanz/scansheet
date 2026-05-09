import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UpdateService {
  static const String _kLastUpdateCheckKey = 'last_update_check_ms';
  static const Duration _autoCheckCooldown = Duration(hours: 18);

  static bool _sessionChecked = false;
  static bool _installPromptOpen = false;

  static bool get _supportsInAppUpdates =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static StreamSubscription<dynamic>? bindInstallListener(
    BuildContext context,
  ) {
    if (!_supportsInAppUpdates) return null;

    return InAppUpdate.installUpdateListener.listen((status) {
      if (!context.mounted) return;
      unawaited(handleInstallStatus(context, status));
    });
  }

  static Future<void> maybeCheckForUpdate(BuildContext context) async {
    if (!_supportsInAppUpdates || _sessionChecked) return;
    _sessionChecked = true;

    final prefs = await SharedPreferences.getInstance();
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final lastCheckMs = prefs.getInt(_kLastUpdateCheckKey) ?? 0;
    if (nowMs - lastCheckMs < _autoCheckCooldown.inMilliseconds) return;

    await prefs.setInt(_kLastUpdateCheckKey, nowMs);
    if (!context.mounted) return;
    await _checkForUpdate(context, userInitiated: false);
  }

  static Future<void> checkForUpdateFromSettings(BuildContext context) async {
    if (!_supportsInAppUpdates) {
      if (context.mounted) {
        _showSnack(
          context,
          'In-app updates are available on Android builds installed from Google Play.',
        );
      }
      return;
    }

    await _checkForUpdate(context, userInitiated: true);
  }

  static Future<void> handleAppResume(BuildContext context) async {
    if (!_supportsInAppUpdates) return;
    await _resumePendingUpdate(context);
  }

  static Future<void> handleInstallStatus(
    BuildContext context,
    Object? status,
  ) async {
    if (!_supportsInAppUpdates || !context.mounted || status is! InstallStatus) {
      return;
    }

    switch (status) {
      case InstallStatus.downloaded:
        await _promptToInstallDownloadedUpdate(context);
        return;
      case InstallStatus.failed:
        _showSnack(
          context,
          'Update download failed. Please try again later.',
          isError: true,
        );
        return;
      case InstallStatus.canceled:
        _showSnack(context, 'Update download canceled.');
        return;
      default:
        return;
    }
  }

  static Future<void> _resumePendingUpdate(BuildContext context) async {
    try {
      final info = await InAppUpdate.checkForUpdate();
      if (!context.mounted) return;

      if (info.installStatus == InstallStatus.downloaded) {
        await _promptToInstallDownloadedUpdate(context);
        return;
      }

      if (info.updateAvailability ==
              UpdateAvailability.developerTriggeredUpdateInProgress &&
          info.immediateUpdateAllowed) {
        await InAppUpdate.performImmediateUpdate();
      }
    } catch (_) {
      // Fail silently when the build is not Play-installed or the API is
      // temporarily unavailable.
    }
  }

  static Future<void> _checkForUpdate(
    BuildContext context, {
    required bool userInitiated,
  }) async {
    try {
      final info = await InAppUpdate.checkForUpdate();
      if (!context.mounted) return;

      if (info.installStatus == InstallStatus.downloaded) {
        await _promptToInstallDownloadedUpdate(context);
        return;
      }

      if (info.updateAvailability ==
              UpdateAvailability.developerTriggeredUpdateInProgress &&
          info.immediateUpdateAllowed) {
        final result = await InAppUpdate.performImmediateUpdate();
        if (context.mounted) {
          _handleUpdateStartResult(
            context,
            result,
            startedFlexibleUpdate: false,
          );
        }
        return;
      }

      if (info.updateAvailability != UpdateAvailability.updateAvailable) {
        if (userInitiated) {
          _showSnack(context, "You're already on the latest version.");
        }
        return;
      }

      if (info.immediateUpdateAllowed && _shouldUseImmediateUpdate(info)) {
        final shouldStart = userInitiated ||
            await _showUpdateDialog(
              context,
              title: 'Critical update available',
              message:
                  '${_baseUpdateMessage(info)} This update should be installed before you keep using the latest build.',
              confirmLabel: 'Update now',
            );

        if (!shouldStart || !context.mounted) return;

        final result = await InAppUpdate.performImmediateUpdate();
        if (context.mounted) {
          _handleUpdateStartResult(
            context,
            result,
            startedFlexibleUpdate: false,
          );
        }
        return;
      }

      if (info.flexibleUpdateAllowed) {
        final shouldStart = await _showUpdateDialog(
          context,
          title: 'Update available',
          message:
              '${_baseUpdateMessage(info)} Download it in the background and install when you are ready to restart.',
          confirmLabel: 'Download update',
        );

        if (!shouldStart || !context.mounted) return;

        final result = await InAppUpdate.startFlexibleUpdate();
        if (context.mounted) {
          _handleUpdateStartResult(
            context,
            result,
            startedFlexibleUpdate: true,
          );
        }
        return;
      }

      if (userInitiated) {
        _showSnack(
          context,
          'An update is available, but Google Play is not allowing an in-app install for this build yet.',
        );
      }
    } catch (error) {
      if (!context.mounted || !userInitiated) return;

      _showSnack(
        context,
        _friendlyErrorMessage(error, userInitiated: userInitiated),
        isError: userInitiated,
      );
    }
  }

  static bool _shouldUseImmediateUpdate(AppUpdateInfo info) {
    final stalenessDays = info.clientVersionStalenessDays ?? 0;
    return info.updatePriority >= 4 ||
        stalenessDays >= 7 ||
        !info.flexibleUpdateAllowed;
  }

  static String _baseUpdateMessage(AppUpdateInfo info) {
    final details = <String>[];

    if (info.availableVersionCode != null) {
      details.add('version code ${info.availableVersionCode}');
    }

    final stalenessDays = info.clientVersionStalenessDays;
    if (stalenessDays != null && stalenessDays > 0) {
      final label = stalenessDays == 1 ? 'day' : 'days';
      details.add('available for $stalenessDays $label');
    }

    if (details.isEmpty) {
      return 'A newer version is ready in Google Play.';
    }

    return 'A newer version is ready in Google Play (${details.join(', ')}).';
  }

  static void _handleUpdateStartResult(
    BuildContext context,
    AppUpdateResult result, {
    required bool startedFlexibleUpdate,
  }) {
    switch (result) {
      case AppUpdateResult.success:
        if (startedFlexibleUpdate) {
          _showSnack(
            context,
            'Update download started. We will prompt you to restart once it is ready.',
          );
        }
        return;
      case AppUpdateResult.userDeniedUpdate:
        _showSnack(context, 'Update postponed.');
        return;
      case AppUpdateResult.inAppUpdateFailed:
        _showSnack(
          context,
          'Could not start the update right now.',
          isError: true,
        );
        return;
    }
  }

  static Future<void> _promptToInstallDownloadedUpdate(
    BuildContext context,
  ) async {
    if (_installPromptOpen || !context.mounted) return;
    _installPromptOpen = true;

    try {
      final installNow = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Install update now?'),
              content: const Text(
                'The new version has finished downloading. Restart the app to complete the update.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Later'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Restart app'),
                ),
              ],
            ),
          ) ??
          false;

      if (!installNow || !context.mounted) return;
      await InAppUpdate.completeFlexibleUpdate();
    } catch (_) {
      if (context.mounted) {
        _showSnack(
          context,
          'Could not complete the update install.',
          isError: true,
        );
      }
    } finally {
      _installPromptOpen = false;
    }
  }

  static Future<bool> _showUpdateDialog(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Later'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(confirmLabel),
              ),
            ],
          ),
        ) ??
        false;
  }

  static String _friendlyErrorMessage(
    Object error, {
    required bool userInitiated,
  }) {
    final raw = error.toString();

    if (raw.contains('ERROR_API_NOT_AVAILABLE')) {
      return userInitiated
          ? 'In-app updates only work for builds installed from Google Play. Internal app sharing or production/test tracks can be used to verify this.'
          : 'Update check skipped because this build is not installed from Google Play.';
    }

    if (raw.contains('channel-error') || raw.contains('not implemented')) {
      return 'This platform does not support Google Play in-app updates.';
    }

    return userInitiated
        ? 'Could not check for updates right now.'
        : '';
  }

  static void _showSnack(
    BuildContext context,
    String message, {
    bool isError = false,
  }) {
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: isError
            ? Theme.of(context).colorScheme.error
            : Theme.of(context).colorScheme.primary,
      ),
    );
  }
}
