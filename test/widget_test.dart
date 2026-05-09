// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'dart:io';

import 'package:batchqr/core/services/history_service.dart';
import 'package:batchqr/core/services/scan_history_service.dart';
import 'package:batchqr/core/services/scan_session_service.dart';
import 'package:batchqr/main.dart';
import 'package:batchqr/core/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final hivePath =
        '${Directory.systemTemp.path}${Platform.pathSeparator}batchqr_test_hive';
    Hive.init(hivePath);
    await HistoryService.init();
    await ScanHistoryService.init();
    await ScanSessionService.init();
  });

  testWidgets('App shell renders bottom navigation tabs', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => ThemeProvider(initialThemeMode: ThemeMode.dark),
        child: const MyApp(showOnboarding: false),
      ),
    );

    expect(find.text('Create'), findsOneWidget);
    expect(find.text('Batch'), findsOneWidget);
    expect(find.text('Scan'), findsOneWidget);
    expect(find.text('History'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);

    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();

    expect(find.byType(Scaffold), findsWidgets);
  });
}
