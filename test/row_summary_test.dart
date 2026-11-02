import 'package:flutter_test/flutter_test.dart';
import 'package:scansheet/features/scan/models/scan_session.dart';
import 'package:scansheet/features/sheet/row_summary.dart';

SessionRow _row(int i, List<String> values) =>
    SessionRow(rowIndex: i, values: values, scannedAt: DateTime(2026));

ScanSession _sheet(List<SessionColumn> columns) => ScanSession(
  id: 's',
  name: 'Sheet',
  columns: columns,
  createdAt: DateTime(2026),
);

void main() {
  group('stock count', () {
    final session = _sheet(const [
      SessionColumn(name: 'SKU', type: SessionColumnType.scan),
      SessionColumn(
        name: 'Item',
        type: SessionColumnType.fromList,
        listField: 'Item',
      ),
      SessionColumn(
        name: 'Qty',
        type: SessionColumnType.manual,
        isNumeric: true,
      ),
      SessionColumn(name: 'Bin', type: SessionColumnType.fixed),
      SessionColumn(name: 'Timestamp', type: SessionColumnType.timestamp),
    ]);
    final rows = [
      _row(0, ['8901', 'Honey 500 g', '16', 'B4-12', '2026-11-02 22:48']),
      _row(1, ['8902', 'Peanut butter', '14', 'B4-12', '2026-11-02 22:52']),
    ];

    test(
      'the item name leads, with the code under it and Qty on the right',
      () {
        final s = RowSummaries(session, rows).of(rows[1]);
        expect(s.title, 'Peanut butter');
        expect(s.code, '8902');
        expect(s.titleIsCode, isFalse);
        expect(s.qty, '14');
      },
    );

    test('a Bin on every row is shown once, not on each row', () {
      final summaries = RowSummaries(session, rows);
      expect(summaries.shared, [(name: 'Bin', value: 'B4-12')]);
      expect(summaries.of(rows[0]).details, isEmpty);
    });

    test('once the counter moves to another bin, rows group by bin', () {
      final mixed = [
        ...rows,
        _row(2, ['8903', 'Oats', '3', 'B4-12', '']),
        _row(3, ['8904', 'Rice', '5', 'B4-13', '']),
        _row(4, ['8905', 'Salt', '2', 'B4-13', '']),
        _row(5, ['8906', 'Tea', '8', 'B4-13', '']),
      ];
      final summaries = RowSummaries(session, mixed);
      expect(summaries.shared, isEmpty);
      expect(summaries.groupColumn, 3);
      expect(summaries.of(mixed[5]).details, isEmpty);
      final runs = summaries.runs(mixed.reversed.toList());
      expect(runs.map((r) => (r.value, r.rows.length)), [
        ('B4-13', 3),
        ('B4-12', 3),
      ]);
    });

    test('a value that flips row by row stays on each row', () {
      final mixed = [
        _row(0, ['8901', 'Honey', '1', 'Main', '']),
        _row(1, ['8902', 'Oats', '1', 'Gate 2', '']),
        _row(2, ['8903', 'Rice', '1', 'Main', '']),
        _row(3, ['8904', 'Salt', '1', 'Gate 2', '']),
      ];
      final summaries = RowSummaries(session, mixed);
      expect(summaries.groupColumn, -1);
      expect(summaries.of(mixed[1]).details, ['Gate 2']);
    });

    test('units add up the Qty column', () {
      expect(RowSummaries(session, rows).units, 30);
    });
  });

  test('a plain scan sheet leads with the code', () {
    final session = _sheet(const [
      SessionColumn(name: 'Code', type: SessionColumnType.scan),
      SessionColumn(name: 'Condition', type: SessionColumnType.pickList),
    ]);
    final rows = [
      _row(0, ['A-1', 'Good']),
      _row(1, ['A-2', 'Damaged']),
    ];
    final summaries = RowSummaries(session, rows);
    final s = summaries.of(rows[1]);
    expect(s.title, 'A-2');
    expect(s.titleIsCode, isTrue);
    expect(s.code, isNull);
    expect(s.qty, isNull);
    expect(s.pick, 'Damaged');
    expect(s.details, isEmpty);
    expect(summaries.units, isNull);
    // No choices or default, so nothing counts as the usual one.
    expect(s.pickIsException, isFalse);
    expect(summaries.exceptions, isEmpty);
  });

  group('asset audit', () {
    final session = _sheet(const [
      SessionColumn(name: 'Asset Code', type: SessionColumnType.scan),
      SessionColumn(name: 'Asset Tag', type: SessionColumnType.manual),
      SessionColumn(
        name: 'Condition',
        type: SessionColumnType.pickList,
        choices: ['Good', 'Damaged', 'Missing'],
      ),
      SessionColumn(name: 'Location', type: SessionColumnType.fixed),
    ]);
    final rows = [
      _row(0, ['AST-03401', 'Chair 9', 'Good', 'Floor 3 · West']),
      _row(1, ['AST-03408', 'Desk phone 9', 'Good', 'Floor 3 · West']),
      _row(2, ['AST-03415', 'Laptop 10', 'Good', 'Floor 3 · West']),
      _row(3, ['AST-03422', 'Monitor 10', 'Damaged', 'Meeting room B']),
      _row(4, ['AST-03429', 'Desk phone 10', 'Good', 'Meeting room B']),
      _row(5, ['AST-03457', 'Monitor 11', 'Good', 'Meeting room B']),
    ];
    final summaries = RowSummaries(session, rows);

    test('the typed tag leads, with the code under it', () {
      final s = summaries.of(rows[5]);
      expect(s.title, 'Monitor 11');
      expect(s.code, 'AST-03457');
      expect(s.titleIsCode, isFalse);
      expect(s.details, isEmpty);
    });

    test('only choices other than the usual one are flagged', () {
      expect(summaries.of(rows[5]).pickIsException, isFalse);
      expect(summaries.of(rows[3]).pick, 'Damaged');
      expect(summaries.of(rows[3]).pickIsException, isTrue);
      expect(summaries.exceptions, [(value: 'Damaged', count: 1)]);
    });

    test('rows group by room as the scanner moves', () {
      expect(summaries.groupColumn, 3);
      final runs = summaries.runs(rows.reversed.toList());
      expect(runs.map((r) => r.value), ['Meeting room B', 'Floor 3 · West']);
    });
  });

  test('a numeric value next to the code is not a label', () {
    final session = _sheet(const [
      SessionColumn(name: 'Code', type: SessionColumnType.scan),
      SessionColumn(name: 'Tag', type: SessionColumnType.manual),
    ]);
    final row = _row(0, ['A-1', '42']);
    final s = RowSummaries(session, [row]).of(row);
    expect(s.title, 'A-1');
    expect(s.titleIsCode, isTrue);
    expect(s.details, ['Tag 42']);
  });

  test('barcodes print in their usual digit groups', () {
    expect(RowSummaries.formatCode('8901234567890'), '8 901234 567890');
    expect(RowSummaries.formatCode('012345678905'), '0 12345 67890 5');
    expect(RowSummaries.formatCode('96385074'), '9638 5074');
    expect(RowSummaries.formatCode('AST-03457'), 'AST-03457');
    expect(RowSummaries.formatCode('12345'), '12345');
  });

  test('scannedOn counts rows from one calendar day', () {
    SessionRow at(DateTime t) =>
        SessionRow(rowIndex: 0, values: const [], scannedAt: t);
    final rows = [
      at(DateTime(2026, 11, 2, 23, 59)),
      at(DateTime(2026, 11, 3, 0, 1)),
      at(DateTime(2026, 11, 3, 9)),
    ];
    expect(RowSummaries.scannedOn(rows, DateTime(2026, 11, 3, 12)), 2);
  });

  test('a name lookup that found nothing falls back to the code', () {
    final session = _sheet(const [
      SessionColumn(name: 'Barcode', type: SessionColumnType.scan),
      SessionColumn(name: 'Product', type: SessionColumnType.productInfo),
    ]);
    final row = _row(0, ['0123456789012', '']);
    final s = RowSummaries(session, [row]).of(row);
    expect(s.title, '0123456789012');
    expect(s.code, isNull);
  });

  test('bare numbers keep their column name, words stand alone', () {
    final session = _sheet(const [
      SessionColumn(name: 'Code', type: SessionColumnType.scan),
      SessionColumn(name: 'Price', type: SessionColumnType.manual),
      SessionColumn(name: 'Note', type: SessionColumnType.manual),
    ]);
    final rows = [
      _row(0, ['A', '120', 'Shelf top']),
      _row(1, ['B', '95', '']),
    ];
    final summaries = RowSummaries(session, rows);
    expect(summaries.of(rows[0]).details, ['Price 120', 'Shelf top']);
    expect(summaries.of(rows[1]).details, ['Price 95']);
  });

  test('auto-numbers and timestamps stay out of the details', () {
    final session = _sheet(const [
      SessionColumn(name: '#', type: SessionColumnType.increment),
      SessionColumn(name: 'Ticket', type: SessionColumnType.scan),
      SessionColumn(name: 'Time', type: SessionColumnType.timestamp),
    ]);
    final rows = [
      _row(0, ['1', 'T-100', '10:00']),
      _row(1, ['2', 'T-101', '10:01']),
    ];
    final summaries = RowSummaries(session, rows);
    expect(summaries.shared, isEmpty);
    expect(summaries.of(rows[1]).details, isEmpty);
  });

  test('a single row shares nothing, so every value stays on it', () {
    final session = _sheet(const [
      SessionColumn(name: 'Code', type: SessionColumnType.scan),
      SessionColumn(name: 'Gate', type: SessionColumnType.fixed),
    ]);
    final row = _row(0, ['T-1', 'North']);
    final summaries = RowSummaries(session, [row]);
    expect(summaries.shared, isEmpty);
    expect(summaries.of(row).details, ['North']);
  });
}
