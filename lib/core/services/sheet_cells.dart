/// How synced rows are written to Google Sheets and recognised there again.
///
/// People sort, insert and delete rows in their sheet, so a remembered row
/// number can point at someone else's row by the time an edit goes out.
/// Before overwriting, the sync checks the row still holds the scan it
/// wrote, and if not, looks for it elsewhere in the tab.
class SheetCells {
  SheetCells._();

  /// Cells as sent with `USER_ENTERED`. Codes are forced to text with a
  /// leading apostrophe (Sheets hides it) so `0123` keeps its zero and long
  /// numbers don't turn into `1.23E+12`. Any other cell that would run as
  /// a formula is forced to text too, so a scanned `=…` stays a string.
  static List<String> forSheet(List<String> values, Set<int> textColumns) => [
    for (final (i, v) in values.indexed)
      v.isNotEmpty && (textColumns.contains(i) || _looksLikeFormula(v))
          ? "'$v"
          : v,
  ];

  static bool _looksLikeFormula(String v) =>
      '=+-@'.contains(v[0]) && num.tryParse(v) == null;

  /// Whether a cell read back with `UNFORMATTED_VALUE` holds [sent].
  /// Sheets turns typed numbers into numbers and timestamps into date
  /// serials, so those compare by value.
  static bool cellMatches(String sent, Object? read) {
    final s = sent.trim();
    if (read == null || read == '') return s.isEmpty;
    if (read is String) return read.trim() == s;
    if (read is bool) return '$read'.toLowerCase() == s.toLowerCase();
    if (read is num) {
      final n = num.tryParse(s);
      if (n != null) return (n - read).abs() < 1e-9;
      final t = DateTime.tryParse(s);
      return t != null && (_serial(t) - read).abs() < 1.5 / 86400;
    }
    return false;
  }

  /// Sheets' date serial: days since 1899-12-30, wall-clock time.
  static double _serial(DateTime t) =>
      DateTime.utc(
        t.year,
        t.month,
        t.day,
        t.hour,
        t.minute,
        t.second,
      ).difference(DateTime.utc(1899, 12, 30)).inSeconds /
      86400;

  /// Whether [read] (one sheet row) holds [sent] in the [identity] cells.
  static bool rowMatches(
    List<String> sent,
    List<Object?> read,
    List<int> identity,
  ) {
    final cols = _usable(sent, identity);
    if (cols.isEmpty) return false;
    return cols.every(
      (i) => cellMatches(sent[i], i < read.length ? read[i] : null),
    );
  }

  /// The 1-based sheet row in [table] (the whole tab, row 1 first) that
  /// holds [sent], or null if it's gone. Rows matching every cell beat rows
  /// matching only the [identity] cells; ties go to the row nearest [near],
  /// where it was last seen. Rows in [taken] belong to other edits.
  static int? locate({
    required List<String> sent,
    required List<List<Object?>> table,
    required List<int> identity,
    required int near,
    Set<int> taken = const {},
  }) {
    final all = [for (var i = 0; i < sent.length; i++) i];
    int? best;
    var bestScore = -1;
    for (final (k, row) in table.indexed) {
      final sheetRow = k + 1;
      if (taken.contains(sheetRow) || !rowMatches(sent, row, identity)) {
        continue;
      }
      final score = rowMatches(sent, row, all) ? 1 : 0;
      final closer =
          best != null && (sheetRow - near).abs() < (best - near).abs();
      if (score > bestScore || (score == bestScore && closer)) {
        best = sheetRow;
        bestScore = score;
      }
    }
    return best;
  }

  /// Identity cells that hold something; if the row has none, every filled
  /// cell. A blank row never matches, so a cleared row isn't mistaken for
  /// the one we're after.
  static List<int> _usable(List<String> sent, List<int> identity) {
    final filled = [
      for (final i in identity)
        if (i < sent.length && sent[i].trim().isNotEmpty) i,
    ];
    if (filled.isNotEmpty) return filled;
    return [
      for (var i = 0; i < sent.length; i++)
        if (sent[i].trim().isNotEmpty) i,
    ];
  }
}
