import 'package:flutter_test/flutter_test.dart';
import 'package:scansheet/core/services/template_service.dart';
import 'package:scansheet/features/scan/models/scan_session.dart';

void main() {
  final templates = {
    for (final t in TemplateService.getBuiltInTemplates()) t.id: t,
  };
  SessionColumn col(String template, String name) =>
      templates[template]!.columns.firstWhere((c) => c.name == name);

  test('attendance records In or Out', () {
    final status = col('builtin_attendance', 'In / Out');
    expect(status.type, SessionColumnType.pickList);
    expect(status.choices, ['In', 'Out']);
    expect(status.defaultValue, 'In');
  });

  test('attendance fills name and department from the staff list', () {
    final attendance = templates['builtin_attendance']!;
    expect(attendance.listPrompt, isNotNull);
    expect(col('builtin_attendance', 'Name').type, SessionColumnType.fromList);
    expect(col('builtin_attendance', 'Department').listField, 'Department');
  });

  test('without a list, From list columns become typed columns', () {
    final columns = templates['builtin_attendance']!.columnsWithoutList;
    final name = columns.firstWhere((c) => c.name == 'Name');
    expect(name.type, SessionColumnType.manual);
    expect(name.isNumeric, isFalse);
    expect(columns.map((c) => c.name), [
      'ID / Badge',
      'Name',
      'Department',
      'In / Out',
      'Timestamp',
    ]);
    expect(
      templates['builtin_inventory']!.columnsWithoutList,
      templates['builtin_inventory']!.columns,
    );
  });

  test('stock count wants a list and counts Qty per bin', () {
    final stock = templates['builtin_stock_count']!;
    expect(stock.listPrompt, isNotNull);
    expect(stock.columns.first.type, SessionColumnType.scan);
    expect(col('builtin_stock_count', 'Item').listField, 'Item');
    expect(col('builtin_stock_count', 'Qty').isNumeric, isTrue);
    expect(col('builtin_stock_count', 'Bin').askAtStart, isTrue);
  });

  test('inventory counts Qty and asks for the bin', () {
    final qty = col('builtin_inventory', 'Qty');
    expect(qty.isNumeric, isTrue);
    final bin = col('builtin_inventory', 'Bin');
    expect(bin.labelPrefix, 'BIN-');
    expect(bin.askAtStart, isTrue);
  });

  test('production / QC template exists', () {
    final qc = templates['builtin_production_qc']!;
    expect(qc.columns.first.type, SessionColumnType.scan);
    expect(col('builtin_production_qc', 'Result').choices, [
      'Pass',
      'Fail',
      'Rework',
    ]);
    expect(col('builtin_production_qc', 'Batch').askAtStart, isTrue);
  });

  test('new rows start with Number defaults so scans never wait', () {
    final session = ScanSession(
      id: 's',
      name: 'Count',
      createdAt: DateTime(2026),
      columns: templates['builtin_inventory']!.columns,
    );
    final row = session.buildEmptyRow(0);
    expect(row.values[2], '1'); // Qty
    expect(row.values[1], ''); // Item Name stays optional
  });
}
