import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:scansheet/core/services/team_service.dart';
import 'package:scansheet/features/scan/models/scan_session.dart';

void main() {
  group('invite codes', () {
    test('six characters with no look-alikes', () {
      final code = TeamService.newCode(Random(1));
      expect(code, hasLength(6));
      expect(code, isNot(matches(RegExp('[01OIL]'))));
    });

    test('read from a typed code, a spaced code or the QR link', () {
      expect(TeamService.codeFrom('k7q2pm'), 'K7Q2PM');
      expect(TeamService.codeFrom(' K7Q 2PM '), 'K7Q2PM');
      expect(TeamService.codeFrom('scansheet://join/K7Q2PM'), 'K7Q2PM');
      expect(TeamService.codeFrom(TeamService.linkFor('ABC234')), 'ABC234');
      expect(TeamService.codeFrom('K7Q2P'), isNull);
      expect(TeamService.codeFrom('https://example.com'), isNull);
    });
  });

  test('a teammate gets the setup but not the owner’s Same values', () {
    final owner = ScanSession(
      id: 'o',
      name: 'Warehouse audit',
      columns: const [
        SessionColumn(name: 'SKU', type: SessionColumnType.scan),
        SessionColumn(
          name: 'Bin',
          type: SessionColumnType.fixed,
          fixedValue: 'B-12',
          labelPrefix: 'BIN-',
          recentValues: ['B-11', 'B-10'],
        ),
      ],
      createdAt: DateTime(2026),
      destination: SessionDestination.googleSheets,
      spreadsheetId: 'sheet-1',
      warnDuplicates: true,
      unknownCodes: UnknownCodes.flag,
    );
    final team = TeamSheet.fromMap('K7Q2PM', {
      ...TeamSheet.setupOf(owner),
      'ownerUid': 'u1',
      'ownerName': 'Arpan',
    });
    final mine = team.toSession(id: 'm', lookupListId: 'team_K7Q2PM');
    expect(mine.teamCode, 'K7Q2PM');
    expect(mine.spreadsheetId, 'sheet-1');
    expect(mine.destination, SessionDestination.googleSheets);
    expect(mine.unknownCodes, UnknownCodes.flag);
    expect(mine.warnDuplicates, isTrue);
    expect(mine.columns[1].labelPrefix, 'BIN-');
    expect(mine.columns[1].recentValues, isEmpty);
    expect(mine.lookupListId, 'team_K7Q2PM');
  });

  test('leaving clears the team code', () {
    final s = ScanSession(
      id: 's',
      name: 'n',
      columns: const [],
      createdAt: DateTime(2026),
      teamCode: 'K7Q2PM',
    );
    expect(ScanSession.fromMap(s.toMap()).teamCode, 'K7Q2PM');
    expect(s.withoutTeam().teamCode, isNull);
    expect(s.withoutTeam().id, 's');
  });

  test('scanning now only while recently heard from', () {
    final now = DateTime(2026, 1, 1, 12);
    TeamMember member(DateTime seen) => TeamMember(
      uid: 'u',
      name: 'R',
      email: 'r@example.com',
      role: 'member',
      access: 'granted',
      scanning: true,
      lastSeen: seen,
    );
    expect(
      member(now.subtract(const Duration(minutes: 1))).scanningAt(now),
      isTrue,
    );
    expect(
      member(now.subtract(const Duration(minutes: 10))).scanningAt(now),
      isFalse,
    );
  });
}
