import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/scan/models/scan_session.dart';
import '../ads/ad_manager.dart';
import 'device_service.dart';
import 'google_sheets_service.dart';
import 'scan_session_service.dart';

/// Free-plan allowance (docs/REDESIGN_PLAN.md, "Free plan and Pro"): new
/// rows a month across every sheet, Google Sheets, Excel and CSV alike.
/// Months are UTC, the same months Firestore's rules check.
@immutable
class Usage {
  /// New rows a month on the free plan.
  static const monthlyRows = 200;

  /// Heads-up threshold.
  static const warnAt = 160;

  /// Google Sheets sheets open at once.
  static const openSheets = 3;

  /// "2026-10": the month [rows] counts.
  final String month;
  final int rows;

  const Usage({required this.month, this.rows = 0});

  static String monthOf(DateTime t) {
    final u = t.toUtc();
    return '${u.year}-${u.month.toString().padLeft(2, '0')}';
  }

  /// This month by [DeviceService.now], which the phone's date can't move.
  static String get current => monthOf(DeviceService.now());

  /// Rows added in the current month, 0 once the month rolls over. A
  /// month ahead of the clock still counts: the clock was turned back.
  int get rowsThisMonth => month.compareTo(current) >= 0 ? rows : 0;

  Map<String, Object?> toJson() => {
    'month': month,
    'monthKey': int.parse(month.replaceAll('-', '')),
    'rowsAdded': rows,
  };

  factory Usage.fromJson(Map<String, Object?> j) => Usage(
    month: switch (j['monthKey']) {
      final int key =>
        '${key ~/ 100}-${(key % 100).toString().padLeft(2, '0')}',
      _ => j['month'] as String? ?? current,
    },
    rows: (j['rowsAdded'] as num?)?.toInt() ?? 0,
  );

  /// The larger of two views, so a stale cache, a lagging server or a
  /// switch of Google account never hands back allowance.
  Usage merge(Usage other) =>
      Usage(month: current, rows: max(rowsThisMonth, other.rowsThisMonth));
}

/// Tracks the free plan. Counted on this phone so it works offline, and
/// mirrored to Firestore: `devices/{id}` for this phone, signed in or not
/// (anonymous Firebase Auth), and `users/{uid}` for the Google account, so
/// clearing data, reinstalling or switching accounts never resets it. The
/// larger count always wins.
///
/// A row past the allowance is still saved, never lost, but locked: it
/// stays out of Google Sheets and Excel/CSV exports until the 1st or an
/// upgrade ([releaseLocked]).
class UsageService {
  UsageService._();
  static final UsageService instance = UsageService._();

  static const _prefsKey = 'usage_v2';

  final _sheets = GoogleSheetsService.instance;

  final ValueNotifier<Usage> usage = ValueNotifier(Usage(month: Usage.current));

  bool _firebaseReady = false;
  String? _email;
  SharedPreferences? _prefs;
  bool _releasing = false;
  Future<void>? _syncing;
  bool _syncAgain = false;

  bool get isPro => AdManager.instance.isPro;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    await DeviceService.refresh();
    usage.value = _readLocal();
    try {
      await Firebase.initializeApp();
      _firebaseReady = true;
    } catch (e) {
      debugPrint('Firebase unavailable, usage stays local: $e');
    }
    _email = _sheets.currentUser?.email;
    _sheets.signedInNotifier.addListener(_onAccountChanged);
    AdManager.instance.isProNotifier.addListener(_onProChanged);
    unawaited(_sync());
  }

  /// The month may have turned while the app was away.
  Future<void> onResume() async {
    await DeviceService.refresh();
    await _sync();
  }

  void _onProChanged() {
    if (isPro) unawaited(releaseLocked());
  }

  void _onAccountChanged() {
    final email = _sheets.currentUser?.email;
    if (email == _email) return;
    _email = email;
    if (email == null && _firebaseReady) {
      unawaited(FirebaseAuth.instance.signOut());
    }
    unawaited(_sync());
  }

  /// New rows left this month; null = unlimited (Pro).
  int? get rowsLeft {
    if (isPro) return null;
    return max(0, Usage.monthlyRows - usage.value.rowsThisMonth);
  }

  /// "37 of 200 rows this month"; null for Pro. Another phone on the
  /// account can push the count past 200; it never shows more.
  String? get summary => isPro
      ? null
      : '${min(usage.value.rowsThisMonth, Usage.monthlyRows)} of '
            '${Usage.monthlyRows} rows this month';

  /// Past the heads-up threshold (or at the limit).
  bool get nearLimit => !isPro && usage.value.rowsThisMonth >= Usage.warnAt;

  /// Whether another Google Sheets sheet can be opened on the free plan.
  bool canOpenSheet() {
    if (isPro) return true;
    final open = ScanSessionService.getAllSessions().where(
      (s) => s.isActive && s.destination == SessionDestination.googleSheets,
    );
    return open.length < Usage.openSheets;
  }

  /// Counts one new row against this month. False when the allowance is
  /// used up: the caller saves the row locked. Edits and Qty merges never
  /// count.
  Future<bool> admitRow() async {
    if (isPro) return true;
    if (rowsLeft == 0) return false;
    await _add(1);
    return true;
  }

  /// Unlocks rows saved past the limit, oldest first, as far as this
  /// month's allowance goes (all of them with Pro). Runs after each sync
  /// with the server and on upgrade.
  Future<void> releaseLocked() async {
    if (_releasing) return;
    _releasing = true;
    try {
      var released = 0;
      for (final (sessionId, row) in ScanSessionService.lockedRows()) {
        if (!isPro && rowsLeft! - released <= 0) break;
        await ScanSessionService.unlockRow(sessionId, row);
        released++;
      }
      if (!isPro && released > 0) await _add(released);
    } finally {
      _releasing = false;
    }
  }

  Future<void> _add(int count) async {
    final next = Usage(
      month: Usage.current,
      rows: usage.value.rowsThisMonth + count,
    );
    usage.value = next;
    await _writeLocal(next);
    unawaited(_pushRemote(next, count));
  }

  // ── Local cache ────────────────────────────────────────────────────────

  Usage _readLocal() {
    final raw = _prefs?.getString(_prefsKey);
    if (raw != null) {
      try {
        return Usage.fromJson(jsonDecode(raw) as Map<String, Object?>);
      } catch (_) {}
    }
    return Usage(month: Usage.current);
  }

  Future<void> _writeLocal(Usage u) async {
    await _prefs?.setString(_prefsKey, jsonEncode(u.toJson()));
  }

  // ── Firestore mirror ───────────────────────────────────────────────────

  /// One sync at a time; a request during one runs it again after.
  Future<void> _sync() async {
    if (_syncing case final running?) {
      _syncAgain = true;
      return running;
    }
    _syncing = () async {
      do {
        _syncAgain = false;
        try {
          // Offline, Firestore writes wait for the network; don't let that
          // hold back rows this phone may already unlock.
          await _pullRemote().timeout(const Duration(seconds: 10));
        } catch (e) {
          debugPrint('Usage sync skipped: $e');
        }
        // After the server's count, so another phone's rows are known.
        await releaseLocked();
      } while (_syncAgain);
    }();
    try {
      await _syncing;
    } finally {
      _syncing = null;
    }
  }

  /// The Firebase user for the signed-in Google account, signing in to
  /// Firebase with the same credential when needed. Null when signed out of
  /// Google or Firebase isn't available.
  Future<User?> firebaseUser() async {
    if (!_firebaseReady) return null;
    final auth = FirebaseAuth.instance;
    final email = _sheets.currentUser?.email;
    if (email == null) return null;
    if (auth.currentUser == null || auth.currentUser!.email != email) {
      final idToken = _sheets.currentUser?.authentication.idToken;
      if (idToken == null) return null;
      await auth.signInWithCredential(
        GoogleAuthProvider.credential(idToken: idToken),
      );
    }
    return auth.currentUser;
  }

  /// Signed in to Firebase: as the Google account, or anonymously when
  /// there's none, so a signed-out phone is counted too.
  Future<bool> _ensureFirebase() async {
    if (!_firebaseReady) return false;
    if (_sheets.currentUser != null) return await firebaseUser() != null;
    final auth = FirebaseAuth.instance;
    if (auth.currentUser == null) await auth.signInAnonymously();
    return auth.currentUser != null;
  }

  /// This phone's doc, and the Google account's when signed in.
  Future<List<DocumentReference<Map<String, dynamic>>>> _docs() async {
    if (!await _ensureFirebase()) return const [];
    final db = FirebaseFirestore.instance;
    final id = await DeviceService.id();
    final uid = _sheets.currentUser == null
        ? null
        : FirebaseAuth.instance.currentUser?.uid;
    return [
      if (id != null) db.collection('devices').doc(id),
      if (uid != null) db.collection('users').doc(uid),
    ];
  }

  /// Sets the clock from the server's, so a phone's date moved ahead (or
  /// back) can't start a new month.
  Future<void> _anchorClock() async {
    final id = await DeviceService.id();
    if (id == null) return;
    final doc = FirebaseFirestore.instance.collection('clock').doc(id);
    await doc.set({'t': FieldValue.serverTimestamp()});
    final snap = await doc.get(const GetOptions(source: Source.server));
    final t = snap.data()?['t'];
    if (t is Timestamp) await DeviceService.anchor(t.toDate());
  }

  Future<void> _pullRemote() async {
    final docs = await _docs();
    if (docs.isEmpty) return;
    await _anchorClock();
    var merged = usage.value;
    for (final doc in docs) {
      final snap = await doc.get();
      if (snap.exists) merged = merged.merge(Usage.fromJson(snap.data()!));
    }
    usage.value = merged.merge(usage.value);
    await _writeLocal(usage.value);
    for (final doc in docs) {
      await doc.set(_remoteFields(doc, usage.value), SetOptions(merge: true));
    }
  }

  Future<void> _pushRemote(Usage u, int added) async {
    try {
      for (final doc in await _docs()) {
        await FirebaseFirestore.instance.runTransaction((tx) async {
          final snap = await tx.get(doc);
          final remote = snap.exists ? Usage.fromJson(snap.data()!) : null;
          // Another phone may have added rows too: add to the server's
          // count, but never report less than this phone has seen.
          final serverRows = remote == null || remote.month != u.month
              ? 0
              : remote.rows + added;
          tx.set(
            doc,
            _remoteFields(
              doc,
              Usage(month: u.month, rows: max(serverRows, u.rows)),
            ),
            SetOptions(merge: true),
          );
        });
      }
    } catch (e) {
      debugPrint('Usage push failed: $e');
    }
  }

  /// The account doc also names its owner; a phone's doc holds only counts.
  Map<String, Object?> _remoteFields(DocumentReference doc, Usage u) => {
    if (doc.parent.id == 'users') 'email': _email,
    ...u.toJson(),
    'updatedAt': FieldValue.serverTimestamp(),
  };
}
