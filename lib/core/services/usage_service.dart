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
import 'google_sheets_service.dart';
import 'scan_session_service.dart';

/// Free-plan allowance (docs/REDESIGN_PLAN.md, "Free plan and Pro"): new
/// rows a month across every sheet, Google Sheets, Excel and CSV alike.
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

  static String monthOf(DateTime t) =>
      '${t.year}-${t.month.toString().padLeft(2, '0')}';

  /// Rows added in the current month (0 once the month rolls over).
  int get rowsThisMonth => month == monthOf(DateTime.now()) ? rows : 0;

  Map<String, Object?> toJson() => {'month': month, 'rowsAdded': rows};

  factory Usage.fromJson(Map<String, Object?> j) => Usage(
    month: j['month'] as String? ?? monthOf(DateTime.now()),
    rows: (j['rowsAdded'] as num?)?.toInt() ?? 0,
  );

  /// The larger of two views, so a stale cache, a lagging server or a
  /// switch of Google account never hands back allowance.
  Usage merge(Usage other) => Usage(
    month: monthOf(DateTime.now()),
    rows: max(rowsThisMonth, other.rowsThisMonth),
  );
}

/// Tracks the free plan. Counted on this phone so it works signed out and
/// offline, and mirrored to `users/{uid}` in Firestore (Firebase Auth with
/// the same Google credential) so other phones on the account add up.
///
/// A row past the allowance is still saved, never lost, but locked: it
/// stays out of Google Sheets and Excel/CSV exports until the 1st or an
/// upgrade ([releaseLocked]).
class UsageService {
  UsageService._();
  static final UsageService instance = UsageService._();

  static const _prefsKey = 'usage_v2';

  final _sheets = GoogleSheetsService.instance;

  final ValueNotifier<Usage> usage = ValueNotifier(
    Usage(month: Usage.monthOf(DateTime.now())),
  );

  bool _firebaseReady = false;
  String? _email;
  SharedPreferences? _prefs;
  bool _releasing = false;

  bool get isPro => AdManager.instance.isPro;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    usage.value = _readLocal();
    try {
      await Firebase.initializeApp();
      _firebaseReady = true;
    } catch (e) {
      debugPrint('Firebase unavailable, usage stays local: $e');
    }
    _sheets.signedInNotifier.addListener(_onAccountChanged);
    AdManager.instance.isProNotifier.addListener(_onProChanged);
    await _onAccountChanged();
    // Signed in, rows unlock once the account's count is in (see below).
    if (_email == null) await releaseLocked();
  }

  void _onProChanged() {
    if (isPro) unawaited(releaseLocked());
  }

  Future<void> _onAccountChanged() async {
    final email = _sheets.currentUser?.email;
    if (email == _email) return;
    _email = email;
    if (email == null) {
      if (_firebaseReady) unawaited(FirebaseAuth.instance.signOut());
      return;
    }
    // Another phone may have used this month's rows; check before
    // unlocking any.
    unawaited(_pullRemote(email).then((_) => releaseLocked()));
  }

  /// New rows left this month; null = unlimited (Pro).
  int? get rowsLeft {
    if (isPro) return null;
    return max(0, Usage.monthlyRows - usage.value.rowsThisMonth);
  }

  /// "37 of 200 rows this month"; null for Pro.
  String? get summary => isPro
      ? null
      : '${usage.value.rowsThisMonth} of ${Usage.monthlyRows} rows this month';

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
  /// month's allowance goes (all of them with Pro). Runs at start, on
  /// resume and on upgrade.
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
      month: Usage.monthOf(DateTime.now()),
      rows: usage.value.rowsThisMonth + count,
    );
    usage.value = next;
    await _writeLocal(next);
    if (_email != null) unawaited(_pushRemote(next, count));
  }

  // ── Local cache ────────────────────────────────────────────────────────

  Usage _readLocal() {
    final raw = _prefs?.getString(_prefsKey);
    if (raw != null) {
      try {
        return Usage.fromJson(jsonDecode(raw) as Map<String, Object?>);
      } catch (_) {}
    }
    return Usage(month: Usage.monthOf(DateTime.now()));
  }

  Future<void> _writeLocal(Usage u) async {
    await _prefs?.setString(_prefsKey, jsonEncode(u.toJson()));
  }

  // ── Firestore mirror ───────────────────────────────────────────────────

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

  Future<DocumentReference<Map<String, dynamic>>?> _doc() async {
    final uid = (await firebaseUser())?.uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance.collection('users').doc(uid);
  }

  Future<void> _pullRemote(String email) async {
    try {
      final doc = await _doc();
      if (doc == null) return;
      final snap = await doc.get();
      if (_email != email) return;
      final merged = snap.exists
          ? usage.value.merge(Usage.fromJson(snap.data()!))
          : usage.value;
      usage.value = merged;
      await _writeLocal(merged);
      await doc.set(_remoteFields(merged), SetOptions(merge: true));
    } catch (e) {
      debugPrint('Usage pull failed: $e');
    }
  }

  Future<void> _pushRemote(Usage u, int added) async {
    try {
      final doc = await _doc();
      if (doc == null) return;
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
          _remoteFields(Usage(month: u.month, rows: max(serverRows, u.rows))),
          SetOptions(merge: true),
        );
      });
    } catch (e) {
      debugPrint('Usage push failed: $e');
    }
  }

  Map<String, Object?> _remoteFields(Usage u) => {
    'email': _email,
    ...u.toJson(),
    'updatedAt': FieldValue.serverTimestamp(),
  };
}
