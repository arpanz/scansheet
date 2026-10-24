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
