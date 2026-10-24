import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scansheet/core/services/lookup_list_service.dart';

LookupList _list(List<List<String>> table, {bool pro = true, int? expected}) =>
    LookupList(
      id: 'l',
      name: 'Staff list',
      headers: table.first,
      rows: const [],
      codeColumn: 0,
      fillColumns: const [1, 2],
      expectedColumn: expected,
      source: const ListSource.file('staff.csv'),
      importedAt: DateTime(2026),
    ).withTable(table, pro: pro);

void main() {
  final staff = [
    ['Badge ID', 'Name', 'Department'],
    ['EMP-0142', 'Rahul Verma', 'Packing'],
    ['emp-0087', 'Sunita Rao', 'Stores'],
    ['012345678905', 'Sample UPC', ''],
  ];

  group('matching', () {
    final list = _list(staff);

    test('trims and ignores case', () {
      expect(list.lookup(' emp-0142 ')?[1], 'Rahul Verma');
      expect(list.lookup('EMP-0087')?[1], 'Sunita Rao');
      expect(list.lookup('EMP-9999'), isNull);
    });

    test('EAN-13 with a leading 0 matches its UPC-A', () {
      expect(list.lookup('0012345678905')?[1], 'Sample UPC');
    });

    test('title and fields come from the list row', () {
      final row = list.lookup('EMP-0142')!;
      expect(list.titleFor(row), 'Rahul Verma');
      expect(list.field(row, 'Department'), 'Packing');
      expect(list.field(row, 'Missing'), '');
    });
  });

  test('free plan keeps the first 100 entries', () {
    final big = [
      ['SKU', 'Item'],
      for (var i = 0; i < 150; i++) ['S$i', 'Item $i'],
    ];
    final free = _list(big, pro: false);
    expect(free.length, LookupListService.freeEntryLimit);
    expect(free.truncatedFrom, 150);
    expect(_list(big).length, 150);
  });

  test('a re-read follows columns by header name', () {
    final list = _list(staff);
    final moved = list.withTable([
      ['Department', 'Badge ID', 'Name'],
      ['Packing', 'EMP-0142', 'Rahul V.'],
    ], pro: true);
    expect(moved.codeColumn, 1);
    expect(moved.titleFor(moved.lookup('EMP-0142')!), 'Rahul V.');
    expect(moved.field(moved.lookup('EMP-0142')!, 'Name'), 'Rahul V.');
  });

  test('expected count parses numbers with separators', () {
    final stock = _list([
      ['SKU', 'Item', 'On hand'],
      ['A1', 'Rice', '1,200'],
      ['A2', 'Salt', ''],
    ], expected: 2);
    expect(stock.expectedFor(stock.lookup('A1')!), 1200);
    expect(stock.expectedFor(stock.lookup('A2')!), isNull);
  });

  test('saves and loads', () {
    final list = _list(staff);
    final back = LookupList.fromMap(list.toMap());
    expect(back.length, list.length);
    expect(back.lookup('EMP-0142')?[2], 'Packing');
    expect(back.source.label, 'staff.csv');
  });

  group('parseFile', () {
    test('csv with BOM, CRLF and blank lines', () {
      final bytes = Uint8List.fromList(
        utf8.encode('﻿Code,Name\r\n8901234567890,Biscuits\r\n,\r\n'),
      );
      expect(LookupListService.parseFile(bytes, 'csv'), [
        ['Code', 'Name'],
        ['8901234567890', 'Biscuits'],
      ]);
    });

    test('xlsx keeps long numeric barcodes as digits', () {
      final excel = Excel.createExcel();
      final sheet = excel[excel.getDefaultSheet()!];
      sheet.appendRow([TextCellValue('Code'), TextCellValue('Name')]);
      sheet.appendRow([
        DoubleCellValue(8901234567890),
        TextCellValue('Biscuits'),
      ]);
      final bytes = Uint8List.fromList(excel.encode()!);
      expect(LookupListService.parseFile(bytes, 'xlsx'), [
        ['Code', 'Name'],
        ['8901234567890', 'Biscuits'],
      ]);
    });
  });
}
