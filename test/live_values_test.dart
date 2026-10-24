import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scansheet/core/theme/app_theme.dart';
import 'package:scansheet/features/scan/models/scan_session.dart';
import 'package:scansheet/features/scan/widgets/scanner/value_sheet.dart';

void main() {
  final session = ScanSession(
    id: 's',
    name: 'Cycle count',
    createdAt: DateTime(2026),
    columns: const [
      SessionColumn(name: 'Code', type: SessionColumnType.scan),
      SessionColumn(
        name: 'Bin',
        type: SessionColumnType.fixed,
        fixedValue: 'B-12',
        labelPrefix: 'BIN-',
        recentValues: ['B-12', 'B-11'],
      ),
      SessionColumn(
        name: 'Batch',
        type: SessionColumnType.fixed,
        labelPrefix: 'LOT',
      ),
    ],
  );

  group('labelFor', () {
    test('strips the prefix, any case', () {
      expect(session.labelFor('BIN-B-13'), (column: 1, value: 'B-13'));
      expect(session.labelFor('bin-c-01'), (column: 1, value: 'c-01'));
      expect(session.labelFor('LOT 4471'), (column: 2, value: '4471'));
    });

    test('ordinary codes and a bare prefix', () {
      expect(session.labelFor('8901234567890'), isNull);
      expect(session.labelFor('BIN-'), (column: 1, value: 'BIN-'));
    });

    test('columns without a prefix never match', () {
      final plain = session.copyWith(
        columns: const [
          SessionColumn(name: 'Gate', type: SessionColumnType.fixed),
        ],
      );
      expect(plain.labelFor('anything'), isNull);
    });
  });

  group('value sheet', () {
    Future<ValueChoice?> open(
      WidgetTester tester, {
      bool starting = false,
      required Future<void> Function() act,
    }) async {
      ValueChoice? result;
      var closed = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () async {
                    result = await showValueSheet(
                      context,
                      column: session.columns[1],
                      starting: starting,
                    );
                    closed = true;
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await act();
      await tester.pumpAndSettle();
      expect(closed, isTrue);
      return result;
    }

    testWidgets('a recent value is used straight away', (tester) async {
      final choice = await open(
        tester,
        act: () async {
          expect(find.text('Bin for the next scans'), findsOneWidget);
          await tester.tap(find.text('B-11'));
        },
      );
      expect((choice as ValueSet).value, 'B-11');
    });

    testWidgets('a typed value is trimmed', (tester) async {
      final choice = await open(
        tester,
        act: () async {
          await tester.enterText(find.byType(TextField), '  C-01 ');
          await tester.tap(find.text('Use'));
        },
      );
      expect((choice as ValueSet).value, 'C-01');
    });

    testWidgets('scan a label', (tester) async {
      final choice = await open(
        tester,
        act: () => tester.tap(find.text('Scan a bin label')),
      );
      expect(choice, isA<ValueScanLabel>());
    });

    testWidgets('ask at start can keep the current value', (tester) async {
      final choice = await open(
        tester,
        starting: true,
        act: () async {
          expect(find.text('Which Bin?'), findsOneWidget);
          await tester.tap(find.text('Keep B-12'));
        },
      );
      expect(choice, isNull);
    });
  });
}
