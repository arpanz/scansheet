import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:home_widget/home_widget.dart';
import 'package:quick_actions/quick_actions.dart';

import '../../features/onboarding/onboarding_screen.dart';
import '../../features/scan/screens/read_code_screen.dart';
import '../../features/scan/screens/scan_session_screen.dart';
import '../utils/app_router.dart';
import 'scan_session_service.dart';
import 'sheet_summary.dart';

class LaunchActions {
  LaunchActions._();

  static const MethodChannel _channel = MethodChannel('scansheet/launch');
  static final QuickActions _quickActions = const QuickActions();
  static GlobalKey<NavigatorState>? _navigatorKey;
  static Timer? _refreshTimer;
  static bool _initialized = false;

  static Future<void> init(GlobalKey<NavigatorState> navigatorKey) async {
    if (!Platform.isAndroid || _initialized) return;
    _initialized = true;
    _navigatorKey = navigatorKey;

    await _quickActions.initialize(_handleAction);
    await _quickActions.setShortcutItems(const [
      ShortcutItem(
        type: 'resume',
        localizedTitle: 'Resume last sheet',
        icon: 'ic_shortcut_resume',
      ),
      ShortcutItem(
        type: 'read',
        localizedTitle: 'Read a code',
        icon: 'ic_shortcut_read',
      ),
    ]);

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'action' && call.arguments is String) {
        unawaited(_handleAction(call.arguments as String));
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final initialAction = await _channel.invokeMethod<String>(
        'getInitialAction',
      );
      if (await OnboardingScreen.shouldShow()) return;
      if (initialAction != null) await _handleAction(initialAction);
    });

    ScanSessionService.changes.addListener(_onSessionsChanged);
    await refreshWidget();
  }

  static Future<void> _handleAction(String action) async {
    if (action != 'resume' && action != 'read') return;
    if (await OnboardingScreen.shouldShow()) return;
    // A cold-start shortcut can arrive before the first frame mounts the app.
    if (_navigatorKey?.currentState == null) {
      await WidgetsBinding.instance.endOfFrame;
    }
    final navigator = _navigatorKey?.currentState;
    if (navigator == null) return;

    if (action == 'resume') {
      final summary = SheetSummary.inProgress(SheetSummary.all());
      if (summary != null) {
        await navigator.push(
          FadeSlideRoute(page: ScanSessionScreen(session: summary.session)),
        );
        return;
      }
    }
    await navigator.push(FadeSlideRoute(page: const ReadCodeScreen()));
  }

  static void _onSessionsChanged() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer(const Duration(seconds: 1), refreshWidget);
  }

  static Future<void> refreshWidget() async {
    if (!Platform.isAndroid) return;
    final summary = SheetSummary.inProgress(SheetSummary.all());
    await HomeWidget.saveWidgetData<String>(
      'sheet_name',
      summary?.session.name ?? 'No sheet yet',
    );
    await HomeWidget.saveWidgetData<int>('row_count', summary?.rowCount ?? 0);
    await HomeWidget.updateWidget(androidName: 'ScanSheetWidgetProvider');
  }
}
