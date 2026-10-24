import 'package:flutter_test/flutter_test.dart';
import 'package:scansheet/features/scan/models/column_kind.dart';
import 'package:scansheet/features/scan/models/scan_session.dart';

void main() {
  const bin = SessionColumn(
    name: 'Bin',
    type: SessionColumnType.fixed,
    fixedValue: 'B-12',
    labelPrefix: 'BIN-',
    askAtStart: true,
  );

  test('live value fields survive a save and load', () {
    final loaded = SessionColumn.fromMap(bin.withValue('B-13').toMap());
    expect(loaded.fixedValue, 'B-13');
    expect(loaded.labelPrefix, 'BIN-');
    expect(loaded.askAtStart, isTrue);
    expect(loaded.recentValues, ['B-13', 'B-12']);
  });

  test('columns saved before live values load with defaults', () {
    final old = SessionColumn.fromMap({
      'name': 'Aisle',
      'type': 'fixed',
      'fixedValue': 'A',
    });
    expect(old.labelPrefix, isNull);
    expect(old.askAtStart, isFalse);
    expect(old.recentValues, isEmpty);
  });

  test('withValue keeps recents unique, newest first, at most 6', () {
    var col = bin;
    for (final v in ['B-13', 'B-14', 'B-12', 'B-15', 'B-16', 'B-17', 'B-18']) {
      col = col.withValue(v);
    }
    expect(col.recentValues, ['B-18', 'B-17', 'B-16', 'B-15', 'B-12', 'B-14']);
    expect(col.withValue('B-18').recentValues.first, 'B-18');
  });

  test('New sheet detail mentions label prefix and ask at start', () {
    expect(
      ColumnKind.detailOf(bin),
      'Starts as “B-12” · scan BIN- labels · asked at start',
    );
  });
}
