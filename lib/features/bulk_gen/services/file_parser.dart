import 'dart:io';
import 'dart:math';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';

class FileParser {
  /// Parses the chosen file into a general 2D List
  static Future<List<List<dynamic>>> parseFile(PlatformFile file) async {
    final path = file.path;
    if (path == null) return [];

    final extension = file.extension?.toLowerCase() ?? '';

    if (extension == 'csv' || extension == 'txt') {
      final content = await File(path).readAsString();
      return _parseCsv(content);
    } else if (extension == 'xlsx' || extension == 'xls') {
      final bytes = await File(path).readAsBytes();
      return _parseExcel(bytes);
    }

    throw Exception('Unsupported file format: $extension');
  }

  static List<List<dynamic>> _parseExcel(List<int> bytes) {
    var excel = Excel.decodeBytes(bytes);
    if (excel.tables.isEmpty) return [];

    // Parse the first table/sheet
    final sheetName = excel.tables.keys.first;
    final table = excel.tables[sheetName];
    if (table == null) return [];

    List<List<dynamic>> rows = [];
    for (var row in table.rows) {
      if (row.isEmpty) continue;
      // Convert Data cells to literal values
      List<dynamic> parsedRow = row.map((cell) => cell?.value ?? '').toList();
      // Only keep non-empty rows
      if (parsedRow.any((e) => e.toString().trim().isNotEmpty)) {
        rows.add(parsedRow);
      }
    }
    return rows;
  }

  static String _detectDelimiter(String text) {
    if (text.isEmpty) return ',';
    final firstLine = text.contains('\n') ? text.split('\n').first : text;

    final commas = firstLine.split(',').length - 1;
    final pipes = firstLine.split('|').length - 1;
    final tabs = firstLine.split('\t').length - 1;
    final semicolons = firstLine.split(';').length - 1;

    final maxCount = [commas, pipes, tabs, semicolons].reduce(max);

    if (maxCount == 0) return ',';
    if (maxCount == pipes) return '|';
    if (maxCount == tabs) return '\t';
    if (maxCount == semicolons) return ';';
    return ',';
  }

  static String _detectEol(String text) {
    if (text.contains('\r\n')) return '\r\n';
    if (text.contains('\n')) return '\n';
    if (text.contains('\r')) return '\r';
    return '\n';
  }

  static List<List<dynamic>> _parseCsv(String text, {String? delimiter}) {
    if (text.isEmpty) return [];
    final d = delimiter ?? _detectDelimiter(text);
    final eol = _detectEol(text);

    return CsvToListConverter(
      fieldDelimiter: d,
      eol: eol,
      shouldParseNumbers: true,
    ).convert(text);
  }

  static String listToCsv(List<List<dynamic>> data, {String delimiter = ','}) {
    return ListToCsvConverter(fieldDelimiter: delimiter).convert(data);
  }
}
