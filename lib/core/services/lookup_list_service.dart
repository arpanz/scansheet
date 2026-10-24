import 'dart:convert';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'google_sheets_service.dart';

/// Lists of known codes (a staff roster, stock on hand, an asset register)
/// imported once and checked against while scanning. Stored in Hive and
/// reusable across sheets.
class LookupListService {
  static const _boxName = 'lookup_lists';
  static Box? _box;

  /// Free plan keeps this many entries per list; Pro keeps them all.
  static const freeEntryLimit = 100;

  static Box get _safeBox {
    assert(_box != null, 'Call LookupListService.init() before use.');
    return _box!;
  }

  static Future<void> init() async {
    _box = await Hive.openBox(_boxName);
  }

  /// Fires whenever a list is added, refreshed, renamed or deleted.
  static ValueListenable<Box> get changes => _safeBox.listenable();

  static List<LookupList> all() {
    final lists = <LookupList>[];
    for (final key in _safeBox.keys) {
      final raw = _safeBox.get(key);
      if (raw == null) continue;
      try {
        lists.add(LookupList.fromMap(Map<String, dynamic>.from(raw as Map)));
      } catch (_) {}
    }
    lists.sort((a, b) => b.importedAt.compareTo(a.importedAt));
    return lists;
  }

  static LookupList? get(String? id) {
    if (id == null) return null;
    final raw = _safeBox.get(id);
    if (raw == null) return null;
    try {
      return LookupList.fromMap(Map<String, dynamic>.from(raw as Map));
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(LookupList list) =>
      _safeBox.put(list.id, list.toMap());

  static Future<void> delete(String id) => _safeBox.delete(id);

  /// Reads a Google Sheets list again. Returns the updated list, or null when
  /// it isn't from Google Sheets or the read failed (the old copy is kept).
  static Future<LookupList?> refresh(
    LookupList list, {
    required bool pro,
  }) async {
    final source = list.source;
    if (source.spreadsheetId == null || source.tab == null) return null;
    try {
      final table = await GoogleSheetsService.instance.readTab(
        source.spreadsheetId!,
        source.tab!,
      );
      if (table.length < 2) return null;
      final updated = list.withTable(table, pro: pro);
      await save(updated);
      return updated;
    } catch (_) {
      return null;
    }
  }

  /// Rows of an .xlsx (first sheet) or .csv file, blank rows dropped.
  static List<List<String>> parseFile(Uint8List bytes, String extension) {
    final List<List<String>> rows;
    if (extension.toLowerCase() == 'csv') {
      var text = utf8.decode(bytes, allowMalformed: true);
      if (text.startsWith('﻿')) text = text.substring(1);
      rows = const CsvToListConverter(shouldParseNumbers: false, eol: '\n')
          .convert(text.replaceAll('\r\n', '\n'))
          .map((r) => r.map((c) => '$c'.trim()).toList())
          .toList();
    } else {
      final excel = Excel.decodeBytes(bytes);
      final sheet = excel.tables.values.firstOrNull;
      rows = [
        for (final row in sheet?.rows ?? const <List<Data?>>[])
          [for (final cell in row) _cellText(cell?.value)],
      ];
    }
    return rows.where((r) => r.any((c) => c.isNotEmpty)).toList();
  }

  // Spreadsheets store long barcodes as numbers; keep them as plain digits.
  static String _cellText(CellValue? value) => switch (value) {
    null => '',
    TextCellValue(:final value) => (value.text ?? '').trim(),
    DoubleCellValue(:final value) when value == value.truncateToDouble() =>
      value.toStringAsFixed(0),
    _ => value.toString().trim(),
  };
}

/// Where a list came from, so it can be read again.
class ListSource {
  final String? fileName;
  final String? spreadsheetId;
  final String? spreadsheetTitle;
  final String? tab;

  const ListSource.file(this.fileName)
    : spreadsheetId = null,
      spreadsheetTitle = null,
      tab = null;

  const ListSource.sheets({
    required String this.spreadsheetId,
    required String this.spreadsheetTitle,
    required String this.tab,
  }) : fileName = null;

  const ListSource._(
    this.fileName,
    this.spreadsheetId,
    this.spreadsheetTitle,
    this.tab,
  );

  bool get isSheets => spreadsheetId != null;

  /// "from HR roster" / "from staff.xlsx".
  String get label => isSheets ? '$spreadsheetTitle › $tab' : fileName ?? '';

  Map<String, dynamic> toMap() => {
    'fileName': fileName,
    'spreadsheetId': spreadsheetId,
    'spreadsheetTitle': spreadsheetTitle,
    'tab': tab,
  };

  factory ListSource.fromMap(Map map) => ListSource._(
    map['fileName'] as String?,
    map['spreadsheetId'] as String?,
    map['spreadsheetTitle'] as String?,
    map['tab'] as String?,
  );
}

class LookupList {
  final String id;
  final String name;
  final List<String> headers;
  final List<List<String>> rows;
  final int codeColumn;

  /// Columns ticked "Fill in when scanned": added as From list columns when
  /// the list is attached to a new sheet.
  final List<int> fillColumns;

  /// Column holding the expected count, for stock counts. Null = none.
  final int? expectedColumn;
  final ListSource source;
  final DateTime importedAt;

  /// Entries in the file before the free plan cut it down, 0 if not cut.
  final int truncatedFrom;

  LookupList({
    required this.id,
    required this.name,
    required this.headers,
    required this.rows,
    required this.codeColumn,
    required this.fillColumns,
    required this.expectedColumn,
    required this.source,
    required this.importedAt,
    this.truncatedFrom = 0,
  });

  late final Map<String, List<String>> _index = {
    for (final row in rows)
      if (codeColumn < row.length && row[codeColumn].isNotEmpty)
        normalize(row[codeColumn]): row,
  };

  int get length => _index.length;

  /// The list row for [code], or null when it isn't on the list.
  List<String>? lookup(String code) => _index[normalize(code)];

  /// One field of [row] by header name, '' if missing.
  String field(List<String> row, String header) {
    final i = headers.indexOf(header);
    return i >= 0 && i < row.length ? row[i] : '';
  }

  int? expectedFor(List<String> row) {
    final i = expectedColumn;
    if (i == null || i >= row.length) return null;
    return num.tryParse(row[i].replaceAll(',', ''))?.round();
  }

  /// The best human name for a row: the first filled-in column that isn't
  /// the code ("Rahul Verma" rather than "EMP-0142").
  String titleFor(List<String> row) {
    for (final i in fillColumns) {
      if (i < row.length && row[i].isNotEmpty) return row[i];
    }
    return codeColumn < row.length ? row[codeColumn] : '';
  }

  /// Codes compare trimmed and case-insensitive, and a 13-digit EAN with a
  /// leading 0 matches its 12-digit UPC-A form.
  static String normalize(String code) {
    var c = code.trim().toUpperCase();
    if (c.length == 13 && c.startsWith('0') && _digits.hasMatch(c)) {
      c = c.substring(1);
    }
    return c;
  }

  static final _digits = RegExp(r'^\d+$');

  /// A copy with new contents read from the same source; headers are kept
  /// by name so a reordered sheet still lines up.
  LookupList withTable(List<List<String>> table, {required bool pro}) {
    final newHeaders = table.first;
    int? remap(int? i) {
      if (i == null || i >= headers.length) return null;
      final at = newHeaders.indexOf(headers[i]);
      return at < 0 ? null : at;
    }

    final data = table.skip(1).toList();
    final keep = pro ? data : data.take(LookupListService.freeEntryLimit);
    return LookupList(
      id: id,
      name: name,
      headers: newHeaders,
      rows: keep.toList(),
      codeColumn: remap(codeColumn) ?? codeColumn,
      fillColumns: [for (final i in fillColumns) ?remap(i)],
      expectedColumn: remap(expectedColumn),
      source: source,
      importedAt: DateTime.now(),
      truncatedFrom: !pro && data.length > LookupListService.freeEntryLimit
          ? data.length
          : 0,
    );
  }

  LookupList copyWith({String? name}) => LookupList(
    id: id,
    name: name ?? this.name,
    headers: headers,
    rows: rows,
    codeColumn: codeColumn,
    fillColumns: fillColumns,
    expectedColumn: expectedColumn,
    source: source,
    importedAt: importedAt,
    truncatedFrom: truncatedFrom,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'headers': headers,
    'rows': rows,
    'codeColumn': codeColumn,
    'fillColumns': fillColumns,
    'expectedColumn': expectedColumn,
    'source': source.toMap(),
    'importedAt': importedAt.toIso8601String(),
    'truncatedFrom': truncatedFrom,
  };

  factory LookupList.fromMap(Map map) => LookupList(
    id: map['id'] as String,
    name: map['name'] as String,
    headers: List<String>.from(map['headers'] as List),
    rows: [for (final r in map['rows'] as List) List<String>.from(r as List)],
    codeColumn: map['codeColumn'] as int,
    fillColumns: List<int>.from(map['fillColumns'] as List? ?? const []),
    expectedColumn: map['expectedColumn'] as int?,
    source: ListSource.fromMap(map['source'] as Map),
    importedAt: DateTime.parse(map['importedAt'] as String),
    truncatedFrom: map['truncatedFrom'] as int? ?? 0,
  );
}
