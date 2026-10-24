import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../features/scan/models/scan_session.dart';
import 'google_sheets_service.dart';
import 'lookup_list_service.dart';
import 'scan_session_service.dart';
import 'sheets_sync_service.dart';
import 'usage_service.dart';

/// "Scan together": several phones scanning into one Google Sheet.
///
/// Firestore holds `teams/{code}` (the sheet's setup and owner), its
/// `members/{uid}` (who joined, Drive access, live status) and, when the
/// sheet checks against a list, `data/list`. Rows never go through
/// Firestore: every phone appends straight to the spreadsheet.
class TeamService {
  TeamService._();
  static final TeamService instance = TeamService._();

  static const _codeChars = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  static const codeLength = 6;

  /// Firestore documents stop at 1 MiB; bigger lists stay on the owner's
  /// phone and teammates scan without them.
  static const _maxListBytes = 900 * 1024;

  CollectionReference<Map<String, dynamic>> get _teams =>
      FirebaseFirestore.instance.collection('teams');

  final _watches = <String, StreamSubscription<Object?>>{};
  final _lastPresence = <String, DateTime>{};

  static String newCode([Random? random]) {
    final r = random ?? Random.secure();
    return String.fromCharCodes(
      List.generate(
        codeLength,
        (_) => _codeChars.codeUnitAt(r.nextInt(_codeChars.length)),
      ),
    );
  }

  /// What the QR code and invite link carry.
  static String linkFor(String code) => 'scansheet://join/$code';

  /// A code from typed text, a pasted invite or a scanned QR; null if none.
  static String? codeFrom(String text) {
    final cleaned = text.trim().toUpperCase();
    final match = RegExp(
      '(?:JOIN/|^)([$_codeChars]{$codeLength})\$',
    ).firstMatch(cleaned.replaceAll(RegExp(r'[\s-]'), ''));
    return match?.group(1);
  }

  Future<String> _uid() async {
    final user = await UsageService.instance.firebaseUser();
    if (user == null) throw TeamException('Sign in with Google first.');
    return user.uid;
  }

  // ── Owner ──────────────────────────────────────────────────────────────

  /// Shares [session] and returns it with its new [ScanSession.teamCode].
  Future<ScanSession> share(ScanSession session) async {
    if (session.destination != SessionDestination.googleSheets ||
        session.spreadsheetId == null) {
      throw TeamException('Only Google Sheets sheets can be shared.');
    }
    final uid = await _uid();
    final account = GoogleSheetsService.instance.currentUser!;
    final list = LookupListService.get(session.lookupListId);
    String? listJson;
    if (list != null) {
      listJson = jsonEncode(list.toMap());
      if (listJson.length > _maxListBytes) listJson = null;
    }
    late String code;
    for (var attempt = 0; ; attempt++) {
      code = newCode();
      final doc = _teams.doc(code);
      final created = await FirebaseFirestore.instance.runTransaction((
        tx,
      ) async {
        if ((await tx.get(doc)).exists) return false;
        tx.set(doc, {
          ...TeamSheet.setupOf(session),
          'ownerUid': uid,
          'ownerName': account.displayName ?? account.email,
          'active': true,
          'hasList': listJson != null,
          'listName': list?.name,
          'listUpdatedAt': list == null
              ? null
              : Timestamp.fromDate(list.importedAt),
          'createdAt': FieldValue.serverTimestamp(),
        });
        return true;
      });
      if (created) break;
      if (attempt > 4) throw TeamException('Couldn’t make an invite code.');
    }
    await _teams.doc(code).collection('members').doc(uid).set({
      'name': account.displayName ?? account.email,
      'email': account.email,
      'role': 'owner',
      'access': 'granted',
      'scanning': false,
      'rows': ScanSessionService.getRowCount(session.id),
      'lastSeen': FieldValue.serverTimestamp(),
      'joinedAt': FieldValue.serverTimestamp(),
    });
    if (listJson != null) {
      await _teams.doc(code).collection('data').doc('list').set({
        'json': listJson,
      });
    }
    final shared = session.copyWith(teamCode: code);
    await ScanSessionService.saveSession(shared);
    _watchAsOwner(code, session.spreadsheetId!);
    return shared;
  }

  /// Gives a teammate who joined edit access to the spreadsheet.
  Future<void> grantAccess(TeamSheet team, TeamMember member) async {
    final ref = _teams.doc(team.code).collection('members').doc(member.uid);
    try {
      await GoogleSheetsService.instance.shareWith(
        team.spreadsheetId,
        member.email,
      );
      await ref.update({'access': 'granted'});
    } catch (e) {
      debugPrint('Grant access failed: $e');
      await ref.update({'access': 'failed'});
    }
  }

  Future<void> removeMember(TeamSheet team, TeamMember member) async {
    await _teams.doc(team.code).collection('members').doc(member.uid).delete();
    await GoogleSheetsService.instance.unshare(
      team.spreadsheetId,
      member.email,
    );
  }

  /// Ends sharing: teammates keep their rows but lose access to the
  /// spreadsheet.
  Future<void> stopSharing(ScanSession session) async {
    final code = session.teamCode;
    if (code == null) return;
    final team = await fetch(code);
    await _teams.doc(code).update({'active': false});
    _watches.remove(code)?.cancel();
    if (team != null) {
      final members = await _teams.doc(code).collection('members').get();
      for (final doc in members.docs) {
        final m = TeamMember.fromDoc(doc);
        if (m.role != 'owner') {
          await GoogleSheetsService.instance.unshare(
            team.spreadsheetId,
            m.email,
          );
        }
      }
    }
    await ScanSessionService.saveSession(session.withoutTeam());
  }

  /// Sends a refreshed list to teammates (they pick it up next time they
  /// open the scanner).
  Future<void> pushList(ScanSession session, LookupList list) async {
    final code = session.teamCode;
    if (code == null) return;
    try {
      final team = await fetch(code);
      if (team == null || !team.active || team.ownerUid != await _uid()) {
        return;
      }
      final json = jsonEncode(list.toMap());
      if (json.length > _maxListBytes) return;
      await _teams.doc(code).collection('data').doc('list').set({'json': json});
      await _teams.doc(code).update({
        'hasList': true,
        'listName': list.name,
        'listUpdatedAt': Timestamp.fromDate(list.importedAt),
      });
    } catch (e) {
      debugPrint('Team list push failed: $e');
    }
  }

  // ── Teammate ───────────────────────────────────────────────────────────

  Future<TeamSheet?> fetch(String code) async {
    await _uid();
    final snap = await _teams.doc(code).get();
    return snap.exists ? TeamSheet.fromDoc(snap) : null;
  }

  /// Joins [team]: asks for access, copies its list and makes the local
  /// sheet. Joining again returns the sheet already on this phone.
  Future<ScanSession> join(TeamSheet team) async {
    final uid = await _uid();
    final existing = ScanSessionService.getAllSessions()
        .where((s) => s.teamCode == team.code)
        .firstOrNull;
    if (existing != null) return existing;
    final account = GoogleSheetsService.instance.currentUser!;
    final ref = _teams.doc(team.code).collection('members').doc(uid);
    if (team.ownerUid != uid && !(await ref.get()).exists) {
      await ref.set({
        'name': account.displayName ?? account.email,
        'email': account.email,
        'role': 'member',
        'access': 'requested',
        'scanning': false,
        'rows': 0,
        'lastSeen': FieldValue.serverTimestamp(),
        'joinedAt': FieldValue.serverTimestamp(),
      });
    }
    final list = team.hasList ? await _pullList(team) : null;
    final session = team.toSession(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      lookupListId: list?.id,
    );
    await ScanSessionService.saveSession(session);
    _watchAsMember(team.code, team.spreadsheetId, uid);
    return session;
  }

  Future<LookupList?> _pullList(TeamSheet team) async {
    final snap = await _teams
        .doc(team.code)
        .collection('data')
        .doc('list')
        .get();
    final json = snap.data()?['json'] as String?;
    if (json == null) return null;
    final shared = LookupList.fromMap(jsonDecode(json) as Map);
    // Its own id, so it never overwrites a list of the same name here.
    final list = LookupList.fromMap({
      ...shared.toMap(),
      'id': 'team_${team.code}',
    });
    await LookupListService.save(list);
    return list;
  }

  /// Leaves a team sheet. Rows stay on the phone.
  Future<void> leave(ScanSession session) async {
    final code = session.teamCode;
    if (code == null) return;
    try {
      final uid = await _uid();
      await _teams.doc(code).collection('members').doc(uid).delete();
    } catch (e) {
      debugPrint('Leave failed: $e');
    }
    _watches.remove(code)?.cancel();
    await ScanSessionService.saveSession(session.withoutTeam());
  }

  /// Run when the scanner opens on a team sheet: picks up a newer list and
  /// reports whether the owner stopped sharing.
  Future<TeamSheet?> refresh(ScanSession session) async {
    final code = session.teamCode;
    if (code == null) return null;
    try {
      final team = await fetch(code);
      if (team == null) return null;
      final local = LookupListService.get(session.lookupListId);
      final remoteAt = team.listUpdatedAt;
      if (team.hasList &&
          team.ownerUid != await _uid() &&
          (local == null ||
              (remoteAt != null && remoteAt.isAfter(local.importedAt)))) {
        final list = await _pullList(team);
        if (list != null && session.lookupListId != list.id) {
          await ScanSessionService.saveSession(
            session.copyWith(lookupListId: list.id),
          );
        }
      }
      return team;
    } catch (e) {
      debugPrint('Team refresh failed: $e');
      return null;
    }
  }

  // ── Live status ────────────────────────────────────────────────────────

  /// "Scanning now · 58 rows". Row updates are sent at most every 20 s.
  Future<void> reportPresence(
    ScanSession session, {
    required bool scanning,
    required int rows,
  }) async {
    final code = session.teamCode;
    if (code == null) return;
    final now = DateTime.now();
    final last = _lastPresence[code];
    if (scanning &&
        last != null &&
        now.difference(last) < const Duration(seconds: 20)) {
      return;
    }
    _lastPresence[code] = scanning ? now : DateTime(0);
    try {
      final uid = await _uid();
      await _teams.doc(code).collection('members').doc(uid).update({
        'scanning': scanning,
        'rows': rows,
        'lastSeen': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Presence update failed: $e');
    }
  }

  Stream<TeamSheet?> watch(String code) => _teams
      .doc(code)
      .snapshots()
      .map((s) => s.exists ? TeamSheet.fromDoc(s) : null);

  Stream<List<TeamMember>> members(String code) => _teams
      .doc(code)
      .collection('members')
      .orderBy('joinedAt')
      .snapshots()
      .map((q) => q.docs.map(TeamMember.fromDoc).toList());

  // ── Background ─────────────────────────────────────────────────────────

  /// Starts the background work for team sheets on this phone: owners grant
  /// access to teammates who join; teammates retry sync once let in.
  Future<void> start() async {
    for (final session in ScanSessionService.getAllSessions()) {
      final code = session.teamCode;
      final id = session.spreadsheetId;
      if (code == null || id == null || _watches.containsKey(code)) continue;
      try {
        final uid = await _uid();
        final team = await fetch(code);
        if (team == null || !team.active) continue;
        team.ownerUid == uid
            ? _watchAsOwner(code, id)
            : _watchAsMember(code, id, uid);
      } catch (e) {
        debugPrint('Team watch skipped: $e');
        return;
      }
    }
  }

  void _watchAsOwner(String code, String spreadsheetId) {
    _watches[code]?.cancel();
    _watches[code] = _teams
        .doc(code)
        .collection('members')
        .where('access', isEqualTo: 'requested')
        .snapshots()
        .listen((q) async {
          final team = await fetch(code);
          if (team == null || !team.active) return;
          for (final doc in q.docs) {
            await grantAccess(team, TeamMember.fromDoc(doc));
          }
        }, onError: (Object e) => debugPrint('Owner watch: $e'));
  }

  void _watchAsMember(String code, String spreadsheetId, String uid) {
    _watches[code]?.cancel();
    _watches[code] = _teams
        .doc(code)
        .collection('members')
        .doc(uid)
        .snapshots()
        .listen((snap) {
          if (snap.data()?['access'] != 'granted') return;
          final sync = SheetsSyncService.instance;
          sync.forgetMissing(spreadsheetId);
          // Rows that failed while waiting go now, not after their backoff.
          sync.retryNow();
        }, onError: (Object e) => debugPrint('Member watch: $e'));
  }
}

class TeamException implements Exception {
  final String message;
  TeamException(this.message);
  @override
  String toString() => message;
}

/// A shared sheet's setup, as teammates get it when they join.
class TeamSheet {
  final String code;
  final String name;
  final String ownerUid;
  final String ownerName;
  final String spreadsheetId;
  final String? sheetName;
  final List<SessionColumn> columns;
  final UnknownCodes unknownCodes;
  final bool warnDuplicates;
  final bool mergeRepeats;
  final bool showScanConfirmation;
  final String? iconName;
  final bool active;
  final bool hasList;
  final String? listName;
  final DateTime? listUpdatedAt;

  const TeamSheet({
    required this.code,
    required this.name,
    required this.ownerUid,
    required this.ownerName,
    required this.spreadsheetId,
    this.sheetName,
    required this.columns,
    this.unknownCodes = UnknownCodes.ask,
    this.warnDuplicates = false,
    this.mergeRepeats = false,
    this.showScanConfirmation = false,
    this.iconName,
    this.active = true,
    this.hasList = false,
    this.listName,
    this.listUpdatedAt,
  });

  /// The fields of [session] teammates copy. Each phone keeps its own Same
  /// values (one person is in bin B-12, another in B-13).
  static Map<String, Object?> setupOf(ScanSession session) => {
    'name': session.name,
    'spreadsheetId': session.spreadsheetId,
    'sheetName': session.sheetName,
    'columns': [
      for (final c in session.columns)
        c.copyWith(recentValues: const []).toMap(),
    ],
    'unknownCodes': session.unknownCodes.name,
    'warnDuplicates': session.warnDuplicates,
    'mergeRepeats': session.mergeRepeats,
    'showScanConfirmation': session.showScanConfirmation,
    'iconName': session.iconName,
  };

  factory TeamSheet.fromMap(String code, Map<String, dynamic> m) => TeamSheet(
    code: code,
    name: m['name'] as String? ?? 'Team sheet',
    ownerUid: m['ownerUid'] as String,
    ownerName: m['ownerName'] as String? ?? '',
    spreadsheetId: m['spreadsheetId'] as String,
    sheetName: m['sheetName'] as String?,
    columns: [
      for (final c in m['columns'] as List? ?? const [])
        SessionColumn.fromMap(c as Map),
    ],
    unknownCodes: UnknownCodes.values.firstWhere(
      (e) => e.name == m['unknownCodes'],
      orElse: () => UnknownCodes.ask,
    ),
    warnDuplicates: m['warnDuplicates'] as bool? ?? false,
    mergeRepeats: m['mergeRepeats'] as bool? ?? false,
    showScanConfirmation: m['showScanConfirmation'] as bool? ?? false,
    iconName: m['iconName'] as String?,
    active: m['active'] as bool? ?? true,
    hasList: m['hasList'] as bool? ?? false,
    listName: m['listName'] as String?,
    listUpdatedAt: (m['listUpdatedAt'] as Timestamp?)?.toDate(),
  );

  factory TeamSheet.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      TeamSheet.fromMap(doc.id, doc.data()!);

  ScanSession toSession({required String id, String? lookupListId}) =>
      ScanSession(
        id: id,
        name: name,
        columns: columns,
        createdAt: DateTime.now(),
        warnDuplicates: warnDuplicates,
        mergeRepeats: mergeRepeats,
        showScanConfirmation: showScanConfirmation,
        destination: SessionDestination.googleSheets,
        spreadsheetId: spreadsheetId,
        sheetName: sheetName,
        iconName: iconName,
        lookupListId: lookupListId,
        unknownCodes: unknownCodes,
        teamCode: code,
      );
}

class TeamMember {
  final String uid;
  final String name;
  final String email;
  final String role;

  /// requested → granted, or failed when the owner's phone couldn't share
  /// the spreadsheet (one ScanSheet didn't create).
  final String access;
  final bool scanning;
  final int rows;
  final DateTime? lastSeen;

  const TeamMember({
    required this.uid,
    required this.name,
    required this.email,
    required this.role,
    required this.access,
    this.scanning = false,
    this.rows = 0,
    this.lastSeen,
  });

  bool get isOwner => role == 'owner';

  /// Scanning, and heard from in the last 3 minutes (an app killed
  /// mid-scan never says it stopped).
  bool scanningAt(DateTime now) =>
      scanning &&
      lastSeen != null &&
      now.difference(lastSeen!) < const Duration(minutes: 3);

  factory TeamMember.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data() ?? const <String, dynamic>{};
    return TeamMember(
      uid: doc.id,
      name: m['name'] as String? ?? '',
      email: m['email'] as String? ?? '',
      role: m['role'] as String? ?? 'member',
      access: m['access'] as String? ?? 'requested',
      scanning: m['scanning'] as bool? ?? false,
      rows: (m['rows'] as num?)?.toInt() ?? 0,
      lastSeen: (m['lastSeen'] as Timestamp?)?.toDate(),
    );
  }
}
