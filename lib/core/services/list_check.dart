import '../../features/scan/models/scan_session.dart';
import 'lookup_list_service.dart';

/// How a sheet's rows compare with its list: who's here and who isn't
/// (attendance), or counted against expected (stock, when the list has an
/// Expected column).
class ListCheck {
  final LookupList list;

  /// Counted per list code (normalized): the sum of the Qty column when the
  /// sheet has one, else the number of rows.
  final Map<String, int> counted;

  /// Rows whose code isn't on the list.
  final List<SessionRow> notOnList;

  ListCheck._(this.list, this.counted, this.notOnList);

  factory ListCheck(
    LookupList list,
    ScanSession session,
    List<SessionRow> rows,
  ) {
    final scan = session.scanColumnIndices.firstOrNull;
    final qty = session.qtyColumnIndex;
    final counted = <String, int>{};
    final notOnList = <SessionRow>[];
    if (scan != null) {
      for (final row in rows) {
        if (scan >= row.values.length) continue;
        final code = row.values[scan];
        if (code.isEmpty) continue;
        if (list.lookup(code) == null) {
          notOnList.add(row);
          continue;
        }
        final n = qty >= 0 && qty < row.values.length
            ? int.tryParse(row.values[qty].trim()) ?? 1
            : 1;
        final key = LookupList.normalize(code);
        counted[key] = (counted[key] ?? 0) + n;
      }
    }
    return ListCheck._(list, counted, notOnList);
  }

  int get found => counted.length;
  int get total => list.length;
  int get notYet => total - found;
  double get progress => total == 0 ? 0 : found / total;

  /// Stock mode: the list says how many there should be.
  bool get hasExpected => list.expectedColumn != null;

  /// List rows once each, in list order.
  Iterable<List<String>> get _entries sync* {
    final seen = <String>{};
    for (final row in list.rows) {
      if (list.codeColumn >= row.length) continue;
      final key = LookupList.normalize(row[list.codeColumn]);
      if (key.isEmpty || !seen.add(key)) continue;
      yield row;
    }
  }

  String _key(List<String> row) => LookupList.normalize(row[list.codeColumn]);

  /// List rows nobody scanned yet.
  List<List<String>> get notScanned => [
    for (final row in _entries)
      if (!counted.containsKey(_key(row))) row,
  ];

  /// Stock lines: expected vs counted for every list row with an expected
  /// count (uncounted ones count 0).
  List<({List<String> row, int expected, int counted})> get lines => [
    for (final row in _entries)
      if (list.expectedFor(row) case final expected?)
        (row: row, expected: expected, counted: counted[_key(row)] ?? 0),
  ];

  /// Counted, but not the expected amount.
  List<({List<String> row, int expected, int counted})> get offCount => [
    for (final l in lines)
      if (l.counted > 0 && l.counted != l.expected) l,
  ];

  /// Stock: [code] is on the list and its count equals the expected count.
  bool matchesExpected(String code) {
    final row = list.lookup(code);
    final expected = row == null ? null : list.expectedFor(row);
    return expected != null && counted[LookupList.normalize(code)] == expected;
  }

  int get matching =>
      lines.where((l) => l.counted > 0 && l.counted == l.expected).length;

  /// Name of the export's second sheet / tab.
  String get tabName => hasExpected ? 'Count vs expected' : 'Not scanned';

  /// The export's second sheet: list rows not scanned (attendance), or every
  /// line with Expected, Counted and Difference (stock).
  List<List<String>> get table {
    if (!hasExpected) return [list.headers, ...notScanned];
    final expectedCol = list.expectedColumn!;
    final headers = [
      for (final (i, h) in list.headers.indexed)
        if (i != expectedCol) h,
    ];
    return [
      [...headers, 'Expected', 'Counted', 'Difference'],
      for (final l in lines)
        [
          for (final (i, v) in l.row.indexed)
            if (i != expectedCol && i < list.headers.length) v,
          for (var i = l.row.length; i < list.headers.length; i++)
            if (i != expectedCol) '',
          '${l.expected}',
          '${l.counted}',
          '${l.counted - l.expected}',
        ],
    ];
  }
}
