import 'package:flutter_test/flutter_test.dart';
import 'package:scansheet/core/services/sheet_cells.dart';

void main() {
  group('forSheet', () {
    test('codes go in as text so leading zeros survive', () {
      expect(SheetCells.forSheet(['0123456789012', '3', ''], {0, 2}), [
        "'0123456789012",
        '3',
        '',
      ]);
    });

    test('a scanned formula stays a string, numbers stay numbers', () {
      expect(
        SheetCells.forSheet(['=IMPORTXML("x")', '-5', '+abc', 'B-12'], {}),
        ["'=IMPORTXML(\"x\")", '-5', "'+abc", 'B-12'],
      );
    });
  });

  group('cellMatches', () {
    test('text, blanks and numbers Sheets parsed', () {
      expect(SheetCells.cellMatches('0123', '0123'), isTrue);
      expect(SheetCells.cellMatches('0123', 123), isTrue); // older rows
      expect(SheetCells.cellMatches('5', 5.0), isTrue);
      expect(SheetCells.cellMatches('', null), isTrue);
      expect(SheetCells.cellMatches('A1', ''), isFalse);
      expect(SheetCells.cellMatches('6', 5), isFalse);
    });

    test('a timestamp matches the date serial Sheets stored', () {
      expect(
        SheetCells.cellMatches('2026-10-30 14:03:22', 46325.5856712963),
        isTrue,
      );
      expect(SheetCells.cellMatches('2026-10-30 14:03:22', 46325.6), isFalse);
    });
  });

  group('locate', () {
    // Code | Time | Qty, header in row 1.
    const header = <Object?>['Code', 'Time', 'Qty'];
    const sent = ['0042', '2026-10-30 14:03:22', '2'];
    const identity = [0, 1];

    test('finds the row after the sheet was sorted', () {
      final table = [
        header,
        ['0099', 46325.1, 1],
        ['0042', 46325.5856712963, 2],
        ['0007', 46325.2, 4],
      ];
      expect(
        SheetCells.locate(
          sent: sent,
          table: table,
          identity: identity,
          near: 4,
        ),
        3,
      );
    });

    test('still finds it after someone changed its Qty by hand', () {
      final table = [
        header,
        ['0042', 46325.5856712963, 9],
      ];
      expect(
        SheetCells.locate(
          sent: sent,
          table: table,
          identity: identity,
          near: 5,
        ),
        2,
      );
    });

    test('prefers a full match, then the row nearest where it was', () {
      const code = ['0042', '', '2'];
      final table = [
        header,
        ['0042', '', 7],
        ['0042', '', 2],
        [],
        ['0042', '', 2],
      ];
      expect(
        SheetCells.locate(sent: code, table: table, identity: [0], near: 6),
        5,
      );
      expect(
        SheetCells.locate(
          sent: code,
          table: table,
          identity: [0],
          near: 6,
          taken: {5},
        ),
        3,
      );
    });

    test('a row deleted in the sheet is gone, and blanks never match', () {
      final table = [
        header,
        ['0099', 46325.1, 1],
        <Object?>[],
      ];
      expect(
        SheetCells.locate(
          sent: sent,
          table: table,
          identity: identity,
          near: 2,
        ),
        isNull,
      );
      expect(SheetCells.rowMatches(['', ''], [], [0, 1]), isFalse);
    });
  });
}
