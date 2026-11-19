import '../scan/models/scan_session.dart';

/// How one row reads in the sheet's list view.
class RowSummary {
  /// The item's name when a Product info or From list column has one, else
  /// the typed label next to the code (an Asset tag, an Attendee), else the
  /// code.
  final String title;

  /// The code under a name or label title; null when the title is the code.
  final String? code;

  /// The title is the scanned code, drawn like other codes (monospace).
  final bool titleIsCode;

  /// The Qty cell, shown big on the right; null if the sheet has none.
  final String? qty;

  /// The row's pick-list choice ("Good"), shown on the right.
  final String? pick;

  /// [pick] isn't the column's usual choice, so it is flagged ("Damaged").
  final bool pickIsException;

  /// Other filled cells that differ between rows, in column order.
  final List<String> details;

  const RowSummary({
    required this.title,
    this.code,
    this.titleIsCode = false,
    this.qty,
    this.pick,
    this.pickIsException = false,
    this.details = const [],
  });
}

/// Reads a sheet's rows as a list instead of a table: values that are the
/// same on every row (a Bin, a Gate) are pulled out once as [shared], and
/// each row keeps only what tells it apart.
class RowSummaries {
  final ScanSession session;

  /// Columns with one value on every row, shown once above the list.
  final List<({String name, String value})> shared;

  /// A Same value column that changed while scanning (the room moved), so
  /// rows are grouped under its values; -1 when none did.
  final int groupColumn;

  /// Pick-list choices other than the usual one, most common first: the
  /// sheet's exceptions ("8 Damaged").
  final List<({String value, int count})> exceptions;

  /// Sum of the Qty column; null when the sheet has none.
  final int? units;

  final int _code;
  final List<int> _names;
  final int _label;
  final int _qty;
  final int _pick;
  final String _usual;
  final Set<int> _hidden;

  factory RowSummaries(ScanSession session, List<SessionRow> rows) {
    final columns = session.columns;
    final code = session.scanColumnIndices.firstOrNull ?? -1;
    final names = [
      for (final (i, c) in columns.indexed)
        if (c.type == SessionColumnType.productInfo ||
            c.type == SessionColumnType.fromList)
          i,
    ];
    final qty = session.qtyColumnIndex;
    // Templates put the thing's name right after its code (Asset code,
    // Asset tag; Ticket, Attendee), so a typed text column there labels it.
    final next = code + 1;
    final label =
        code >= 0 &&
            next < columns.length &&
            next != qty &&
            columns[next].type == SessionColumnType.manual &&
            !columns[next].isNumeric
        ? next
        : -1;
    final pick = columns.indexWhere(
      (c) => c.type == SessionColumnType.pickList,
    );
    final usual = pick < 0
        ? ''
        : (columns[pick].defaultValue ?? '').trim().isNotEmpty
        ? columns[pick].defaultValue!.trim()
        : columns[pick].choices.firstOrNull?.trim() ?? '';
    // Group only when the value changed in stretches (the scanner moved
    // room to room): two gates scanning at once alternate row by row, and
    // a header over every row would just be noise.
    var group = -1;
    for (var i = 0; i < columns.length && group < 0; i++) {
      if (columns[i].type != SessionColumnType.fixed) continue;
      final values = {for (final r in rows) _cell(r, i)}..remove('');
      if (values.length < 2) continue;
      var stretches = 1;
      for (var r = 1; r < rows.length; r++) {
        if (_cell(rows[r], i) != _cell(rows[r - 1], i)) stretches++;
      }
      if (stretches * 3 <= rows.length) group = i;
    }
    // The time comes from the row itself, and auto-numbers repeat '#'.
    final hidden = <int>{
      code,
      qty,
      pick,
      group,
      ...names,
      for (final (i, c) in columns.indexed)
        if (c.type == SessionColumnType.timestamp ||
            c.type == SessionColumnType.increment)
          i,
    };

    final shared = <({String name, String value})>[];
    if (rows.length > 1) {
      for (var i = 0; i < columns.length; i++) {
        if (hidden.contains(i) || i == label) continue;
        final first = _cell(rows.first, i);
        if (first.isEmpty) continue;
        if (rows.every((r) => _cell(r, i) == first)) {
          shared.add((name: columns[i].name, value: first));
          hidden.add(i);
        }
      }
    }

    final counts = <String, int>{};
    if (usual.isNotEmpty) {
      for (final r in rows) {
        final v = _cell(r, pick);
        if (v.isNotEmpty && v != usual) counts[v] = (counts[v] ?? 0) + 1;
      }
    }
    final exceptions = [
      for (final e in counts.entries) (value: e.key, count: e.value),
    ]..sort((a, b) => b.count.compareTo(a.count));

    final units = qty < 0
        ? null
        : rows.fold<int>(0, (n, r) => n + (int.tryParse(_cell(r, qty)) ?? 0));

    return RowSummaries._(
      session,
      shared,
      group,
      exceptions,
      units,
      code,
      names,
      label,
      qty,
      pick,
      usual,
      hidden,
    );
  }

  RowSummaries._(
    this.session,
    this.shared,
    this.groupColumn,
    this.exceptions,
    this.units,
    this._code,
    this._names,
    this._label,
    this._qty,
    this._pick,
    this._usual,
    this._hidden,
  );

  RowSummary of(SessionRow row) {
    final code = _code < 0 ? '' : _cell(row, _code);
    final name = _names
        .map((i) => _cell(row, i))
        .firstWhere((v) => v.isNotEmpty, orElse: () => '');
    final labelValue = _cell(row, _label);
    final label = labelValue.isNotEmpty && num.tryParse(labelValue) == null
        ? labelValue
        : '';
    final titleColumn = name.isEmpty && label.isNotEmpty ? _label : -1;
    final details = <String>[
      for (var i = 0; i < session.columns.length; i++)
        if (!_hidden.contains(i) &&
            i != titleColumn &&
            _cell(row, i).isNotEmpty)
          _detail(session.columns[i].name, _cell(row, i)),
    ];
    final qty = _cell(row, _qty);
    final pick = _cell(row, _pick);
    final pickIsException =
        _usual.isNotEmpty && pick.isNotEmpty && pick != _usual;

    RowSummary summary(
      String title, {
      String? under,
      bool isCode = false,
      List<String>? rest,
    }) => RowSummary(
      title: title,
      code: under == null || under.isEmpty ? null : under,
      titleIsCode: isCode,
      qty: qty.isEmpty ? null : qty,
      pick: pick.isEmpty ? null : pick,
      pickIsException: pickIsException,
      details: rest ?? details,
    );

    if (name.isNotEmpty) return summary(name, under: code);
    if (label.isNotEmpty) return summary(label, under: code);
    if (code.isNotEmpty) return summary(code, isCode: true);
    // No code or name (a sheet of typed columns): lead with the first cell.
    return summary(
      details.isEmpty ? '—' : details.first,
      rest: details.isEmpty ? const [] : details.sublist(1),
    );
  }

  /// [rows] in display order, split where the [groupColumn] value changes:
  /// one run per stretch scanned in the same room or bin.
  List<({String value, List<SessionRow> rows})> runs(List<SessionRow> rows) {
    final runs = <({String value, List<SessionRow> rows})>[];
    for (final row in rows) {
      final value = _cell(row, groupColumn);
      if (runs.isEmpty || runs.last.value != value) {
        runs.add((value: value, rows: [row]));
      } else {
        runs.last.rows.add(row);
      }
    }
    return runs;
  }

  /// Rows scanned on [day]'s calendar date.
  static int scannedOn(List<SessionRow> rows, DateTime day) => rows
      .where(
        (r) =>
            r.scannedAt.year == day.year &&
            r.scannedAt.month == day.month &&
            r.scannedAt.day == day.day,
      )
      .length;

  /// Barcode digits in their printed groups, easy to check against a label:
  /// EAN-13 "8 901234 567890", UPC-A "0 12345 67890 5", EAN-8 "1234 5678".
  /// Anything else is left as scanned.
  static String formatCode(String code) {
    if (!RegExp(r'^\d+$').hasMatch(code)) return code;
    return switch (code.length) {
      13 => '${code[0]} ${code.substring(1, 7)} ${code.substring(7)}',
      12 =>
        '${code[0]} ${code.substring(1, 6)} ${code.substring(6, 11)} '
            '${code[11]}',
      8 => '${code.substring(0, 4)} ${code.substring(4)}',
      _ => code,
    };
  }

  static String _cell(SessionRow row, int i) =>
      i >= 0 && i < row.values.length ? row.values[i].trim() : '';

  /// A bare number says nothing on its own, so it keeps its column name
  /// ("Price 120"); words read fine alone ("Damaged").
  static String _detail(String column, String value) =>
      num.tryParse(value) == null ? value : '$column $value';
}
