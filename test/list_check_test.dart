import 'package:flutter_test/flutter_test.dart';
import 'package:scansheet/core/services/list_check.dart';
import 'package:scansheet/core/services/lookup_list_service.dart';
import 'package:scansheet/features/scan/models/scan_session.dart';

LookupList _list(List<List<String>> table, {int? expected}) => LookupList(
  id: 'l',
  name: 'List',
  headers: table.first,
  rows: const [],
  codeColumn: 0,
  fillColumns: const [1],
  expectedColumn: expected,
  source: const ListSource.file('list.csv'),
  importedAt: DateTime(2026),
).withTable(table, pro: true);

SessionRow _row(int i, List<String> values, {bool flagged = false}) =>
    SessionRow(
      rowIndex: i,
      values: values,
      scannedAt: DateTime(2026),
      notOnList: flagged,
    );

void main() {
  group('attendance', () {
    final staff = _list([
      ['Badge', 'Name'],
      ['E1', 'Rahul'],
      ['E2', 'Sunita'],
      ['E3', 'Arjun'],
    ]);
    final session = ScanSession(
      id: 's',
      name: 'Shift',
      columns: const [
        SessionColumn(name: 'Badge', type: SessionColumnType.scan),
        SessionColumn(
          name: 'Name',
          type: SessionColumnType.fromList,
          listField: 'Name',
        ),
      ],
      createdAt: DateTime(2026),
      lookupListId: 'l',
      unknownCodes: UnknownCodes.flag,
    );
    final rows = [
      _row(0, ['e1', 'Rahul']),
      _row(1, ['E1', 'Rahul']),
      _row(2, ['X9', ''], flagged: true),
    ];
    final check = ListCheck(staff, session, rows);

    test('counts who is here, not yet and not on the list', () {
      expect(check.found, 1);
      expect(check.total, 3);
      expect(check.notYet, 2);
      expect(check.notOnList.single.rowIndex, 2);
      expect(check.notScanned.map((r) => r[1]), ['Sunita', 'Arjun']);
    });

    test('second sheet lists who is missing', () {
      expect(check.tabName, 'Not scanned');
      expect(check.table, [
        ['Badge', 'Name'],
        ['E2', 'Sunita'],
        ['E3', 'Arjun'],
      ]);
    });

    test('flagged rows carry On list = No', () {
      expect(session.toTableData(rows), [
        ['Badge', 'Name', 'On list'],
        ['e1', 'Rahul', 'Yes'],
        ['E1', 'Rahul', 'Yes'],
        ['X9', '', 'No'],
      ]);
      final skipping = session.copyWith(unknownCodes: UnknownCodes.skip);
      expect(skipping.toTableData(rows).first, ['Badge', 'Name']);
    });
  });

  group('stock', () {
    final stock = _list([
      ['SKU', 'Item', 'On hand'],
      ['A1', 'Rice', '40'],
      ['A2', 'Salt', '5'],
      ['A3', 'Oil', '2'],
    ], expected: 2);
    final session = ScanSession(
      id: 's',
      name: 'Count',
      columns: const [
        SessionColumn(name: 'SKU', type: SessionColumnType.scan),
        SessionColumn(
          name: 'Qty',
          type: SessionColumnType.manual,
          isNumeric: true,
        ),
      ],
      createdAt: DateTime(2026),
      lookupListId: 'l',
    );
    final check = ListCheck(stock, session, [
      _row(0, ['A1', '30']),
      _row(1, ['A1', '7']),
      _row(2, ['A2', '5']),
    ]);

    test('counted is the sum of Qty per code', () {
      expect(check.counted, {'A1': 37, 'A2': 5});
      expect(check.matching, 1);
      expect(check.matchesExpected('a2'), isTrue);
      expect(check.matchesExpected('A1'), isFalse);
      final off = check.offCount.single;
      expect((off.row[1], off.expected, off.counted), ('Rice', 40, 37));
      expect(check.notYet, 1);
    });

    test('second sheet compares every line', () {
      expect(check.tabName, 'Count vs expected');
      expect(check.table, [
        ['SKU', 'Item', 'Expected', 'Counted', 'Difference'],
        ['A1', 'Rice', '40', '37', '-3'],
        ['A2', 'Salt', '5', '5', '0'],
        ['A3', 'Oil', '2', '0', '-2'],
      ]);
    });
  });

  test('session list fields survive save and load', () {
    final session = ScanSession(
      id: 's',
      name: 'n',
      columns: const [
        SessionColumn(
          name: 'Dept',
          type: SessionColumnType.fromList,
          listField: 'Department',
        ),
      ],
      createdAt: DateTime(2026),
      lookupListId: 'l',
      unknownCodes: UnknownCodes.skip,
    );
    final back = ScanSession.fromMap(session.toMap());
    expect(back.lookupListId, 'l');
    expect(back.unknownCodes, UnknownCodes.skip);
    expect(back.columns.single.type, SessionColumnType.fromList);
    expect(back.columns.single.listField, 'Department');
    final row = SessionRow.fromMap(_row(0, ['x'], flagged: true).toMap());
    expect(row.notOnList, isTrue);
    expect(
      ScanSession.fromMap(
        {...session.toMap()}..remove('unknownCodes'),
      ).unknownCodes,
      UnknownCodes.ask,
    );
  });
}
