import 'package:flutter_test/flutter_test.dart';
import 'package:scansheet/features/scan/models/column_kind.dart';
import 'package:scansheet/features/scan/models/scan_session.dart';

void main() {
  ScanSession sheet({
    SessionDestination destination = SessionDestination.googleSheets,
    String? spreadsheetId = 'abc',
    String? sheetName,
    String? spreadsheetTitle,
  }) => ScanSession(
    id: '1',
    name: 'Stock count',
    columns: const [
      SessionColumn(name: 'Item code', type: SessionColumnType.scan),
      SessionColumn(name: 'Serial no.', type: SessionColumnType.scan),
    ],
    createdAt: DateTime(2026, 10, 30),
    destination: destination,
    spreadsheetId: spreadsheetId,
    sheetName: sheetName,
    spreadsheetTitle: spreadsheetTitle,
  );

  test('file and tab survive a save and load', () {
    final saved = sheet(
      spreadsheetTitle: 'Warehouse',
      sheetName: 'Aisle 3',
    ).copyWith(createdFile: true);
    final loaded = ScanSession.fromMap(saved.toMap());
    expect(loaded.spreadsheetTitle, 'Warehouse');
    expect(loaded.createdFile, isTrue);
    expect(loaded.fileAndTab, 'Warehouse › Aisle 3');
  });

  test('sheets saved before file titles load with defaults', () {
    final old = ScanSession.fromMap(
      {...sheet().toMap()}
        ..remove('spreadsheetTitle')
        ..remove('createdFile'),
    );
    expect(old.createdFile, isFalse);
    // Falls back to the sheet's name and the spreadsheet's first tab.
    expect(old.fileAndTab, 'Stock count › first tab');
  });

  test('only Google sheets have a file and tab', () {
    expect(sheet(destination: SessionDestination.localXlsx).fileAndTab, isNull);
    expect(sheet(spreadsheetId: null).fileAndTab, isNull);
  });

  test('scan columns say which scan of the row they are', () {
    final s = sheet();
    expect(
      ColumnKind.detailOf(s.columns[0], scanNumber: 1, scanCount: 2),
      '1st scan of each row · spots repeats',
    );
    expect(
      ColumnKind.detailOf(s.columns[1], scanNumber: 2, scanCount: 2),
      '2nd scan of each row',
    );
    expect(
      ColumnKind.detailOf(s.columns[0], scanNumber: 1),
      'Camera · used to spot repeats',
    );
  });
}
