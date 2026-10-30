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

  test('months are UTC, the months the server checks', () {
    expect(Usage.monthOf(DateTime.utc(2026, 10, 31, 23, 59)), '2026-10');
    expect(Usage.monthOf(DateTime.utc(2026, 11, 1)), '2026-11');
  });

  test('turning the clock back to an earlier month keeps the count', () {
    expect(const Usage(month: '2999-01', rows: 200).rowsThisMonth, 200);
  });

  test('the server doc carries a month key the rules can check', () {
    final json = const Usage(month: '2026-10', rows: 12).toJson();
    expect(json['monthKey'], 202610);
    final back = Usage.fromJson({'monthKey': 202611, 'rowsAdded': 3});
    expect(back.month, '2026-11');
    expect(back.rows, 3);
  });
}
