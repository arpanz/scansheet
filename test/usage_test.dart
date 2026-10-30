import 'package:flutter_test/flutter_test.dart';
import 'package:scansheet/core/services/usage_service.dart';
import 'package:scansheet/features/scan/models/scan_session.dart';

void main() {
  final thisMonth = Usage.monthOf(DateTime.now());

  test('a new month starts the count again', () {
    expect(const Usage(month: '2020-01', rows: 150).rowsThisMonth, 0);
    expect(Usage(month: thisMonth, rows: 150).rowsThisMonth, 150);
  });

  test('merging keeps the higher count, never handing back rows', () {
    final phone = Usage(month: thisMonth, rows: 40);
    final account = Usage(month: thisMonth, rows: 120);
    expect(phone.merge(account).rows, 120);
    expect(account.merge(const Usage(month: '2020-01', rows: 199)).rows, 120);
  });

  test('usage survives a save and load', () {
    final loaded = Usage.fromJson(Usage(month: thisMonth, rows: 7).toJson());
    expect(loaded.month, thisMonth);
    expect(loaded.rows, 7);
  });

  test('rows saved before the lock existed load unlocked', () {
    final row = SessionRow(
      rowIndex: 0,
      values: const ['A1'],
      scannedAt: DateTime(2026),
    );
    final old = row.toMap()..remove('locked');
    expect(SessionRow.fromMap(old).locked, isFalse);
    expect(
      SessionRow.fromMap(row.copyWith(locked: true).toMap()).locked,
      isTrue,
    );
    expect(row.copyWith(locked: true).copyWith(values: ['B2']).locked, isTrue);
  });
}
