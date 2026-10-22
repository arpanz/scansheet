import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/scan/models/scan_session.dart';
import '../ads/ad_manager.dart';
import 'google_sheets_service.dart';
import 'scan_session_service.dart';

/// Free-plan allowance for one Google account (docs/REDESIGN_PLAN.md,
/// "Free plan and Pro" / "Trial and usage tracking").
@immutable
class Usage {
  /// Synced rows a month after the trial.
  static const monthlyRows = 200;

  /// Heads-up threshold.
  static const warnAt = 160;

  /// Google Sheets sheets open at once.
  static const openSheets = 3;

  static const trialLength = Duration(days: 7);

  final DateTime? trialStartedAt;

  /// "2026-10": the month [rowsSynced] counts.
  final String month;
  final int rowsSynced;

  const Usage({this.trialStartedAt, required this.month, this.rowsSynced = 0});

  static String monthOf(DateTime t) =>
      '${t.year}-${t.month.toString().padLeft(2, '0')}';

  /// Rows synced in the current month (0 once the month rolls over).
  int get rowsThisMonth => month == monthOf(DateTime.now()) ? rowsSynced : 0;

  /// The trial hasn't started (no synced row yet) or is still running.
  bool get inTrial =>
      trialStartedAt == null ||
      DateTime.now().isBefore(trialStartedAt!.add(trialLength));

  int get trialDaysLeft {
    if (trialStartedAt == null) return trialLength.inDays;
    final left = trialStartedAt!.add(trialLength).difference(DateTime.now());
    return left.isNegative ? 0 : (left.inHours / 24).ceil();
  }

  Usage copyWith({DateTime? trialStartedAt, String? month, int? rowsSynced}) =>
      Usage(
        trialStartedAt: trialStartedAt ?? this.trialStartedAt,
        month: month ?? this.month,
        rowsSynced: rowsSynced ?? this.rowsSynced,
      );

  Map<String, Object?> toJson() => {
    'trialStartedAt': trialStartedAt?.millisecondsSinceEpoch,
    'month': month,
    'rowsSynced': rowsSynced,
  };

  factory Usage.fromJson(Map<String, Object?> j) => Usage(
    trialStartedAt: switch (j['trialStartedAt']) {
      final int ms => DateTime.fromMillisecondsSinceEpoch(ms),
      final Timestamp ts => ts.toDate(),
      _ => null,
    },
    month: j['month'] as String? ?? monthOf(DateTime.now()),
    rowsSynced: (j['rowsSynced'] as num?)?.toInt() ?? 0,
  );

  /// The larger of two views of the same account, so a stale cache or a
  /// lagging server never hands back allowance.
  Usage merge(Usage other) {
    final starts = [?trialStartedAt, ?other.trialStartedAt]..sort();
    final now = monthOf(DateTime.now());
    return Usage(
      trialStartedAt: starts.firstOrNull,
      month: now,
      rowsSynced: [
        rowsThisMonth,
        other.rowsThisMonth,
      ].reduce((a, b) => a > b ? a : b),
    );
  }
}

/// Tracks the free plan per Google account: a local cache (so offline
/// scanning never waits) mirrored to `users/{uid}` in Firestore through
/// Firebase Auth with the same Google credential.
///
/// Only Google Sheets sync is limited. If Firebase isn't reachable or
/// configured, the local cache still enforces the limits.
class UsageService {
  UsageService._();
  static final UsageService instance = UsageService._();

  static const _prefsPrefix = 'usage_v1_';

  final _sheets = GoogleSheetsService.instance;

  /// Usage for the signed-in account; null when signed out.
  final ValueNotifier<Usage?> usage = ValueNotifier(null);

  /// Sync stopped at the monthly limit with rows still waiting.
  final ValueNotifier<bool> syncPaused = ValueNotifier(false);

  bool _firebaseReady = false;
  String? _email;
  SharedPreferences? _prefs;

  bool get isPro => AdManager.instance.isPro;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    try {
      await Firebase.initializeApp();
      _firebaseReady = true;
    } catch (e) {
      debugPrint('Firebase unavailable, usage stays local: $e');
    }
    _sheets.signedInNotifier.addListener(_onAccountChanged);
    AdManager.instance.isProNotifier.addListener(_onProChanged);
    await _onAccountChanged();
  }

  void _onProChanged() {
    if (isPro) syncPaused.value = false;
  }

  Future<void> _onAccountChanged() async {
    final email = _sheets.currentUser?.email;
    if (email == _email) return;
    _email = email;
    syncPaused.value = false;
    if (email == null) {
      usage.value = null;
      if (_firebaseReady) unawaited(FirebaseAuth.instance.signOut());
      return;
    }
    usage.value = _readLocal(email);
    unawaited(_pullRemote(email));
  }

  /// Rows the next sync may append; null = unlimited.
  int? get rowsAllowed {
    final u = usage.value;
    if (isPro || u == null || u.inTrial) return null;
    final left = Usage.monthlyRows - u.rowsThisMonth;
    return left < 0 ? 0 : left;
  }

  /// "37 of 200 rows this month", "Free week · 5 days left"; null for Pro
  /// or signed out.
  String? get summary {
    final u = usage.value;
    if (isPro || u == null) return null;
    if (u.inTrial) {
      final d = u.trialDaysLeft;
      return 'Free week · $d ${d == 1 ? 'day' : 'days'} left';
    }
    return '${u.rowsThisMonth} of ${Usage.monthlyRows} rows this month';
  }

  /// Past the heads-up threshold (or at the limit), outside the trial.
  bool get nearLimit {
    final u = usage.value;
    return !isPro && u != null && !u.inTrial && u.rowsThisMonth >= Usage.warnAt;
  }

  /// Whether another Google Sheets sheet can be opened on the free plan.
  bool canOpenSheet() {
    if (isPro || (usage.value?.inTrial ?? true)) return true;
    final open = ScanSessionService.getAllSessions().where(
      (s) => s.isActive && s.destination == SessionDestination.googleSheets,
    );
    return open.length < Usage.openSheets;
  }

  /// Called by sync after [count] new rows reached Google Sheets.
  /// Edits and Qty merges never count.
  Future<void> recordSynced(int count) async {
    final email = _email;
    final current = usage.value;
    if (email == null || current == null || count <= 0) return;
    final now = DateTime.now();
    final month = Usage.monthOf(now);
    final next = current.copyWith(
      trialStartedAt: current.trialStartedAt ?? now,
      month: month,
      rowsSynced: current.rowsThisMonth + count,
    );
    usage.value = next;
    await _writeLocal(email, next);
    unawaited(_pushRemote(next, count));
  }

  // ── Local cache ────────────────────────────────────────────────────────

  Usage _readLocal(String email) {
    final raw = _prefs?.getString('$_prefsPrefix$email');
    if (raw != null) {
      try {
        return Usage.fromJson(jsonDecode(raw) as Map<String, Object?>);
      } catch (_) {}
    }
    return Usage(month: Usage.monthOf(DateTime.now()));
  }

  Future<void> _writeLocal(String email, Usage u) async {
    await _prefs?.setString('$_prefsPrefix$email', jsonEncode(u.toJson()));
  }

  // ── Firestore mirror ───────────────────────────────────────────────────

  Future<DocumentReference<Map<String, dynamic>>?> _doc() async {
    if (!_firebaseReady) return null;
    final auth = FirebaseAuth.instance;
    final email = _sheets.currentUser?.email;
    if (auth.currentUser == null || auth.currentUser!.email != email) {
      final google = await _sheets.currentUser?.authentication;
      if (google == null || google.idToken == null) return null;
      await auth.signInWithCredential(
        GoogleAuthProvider.credential(
          idToken: google.idToken,
          accessToken: google.accessToken,
        ),
      );
    }
    final uid = auth.currentUser?.uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance.collection('users').doc(uid);
  }

  Future<void> _pullRemote(String email) async {
    try {
      final doc = await _doc();
      if (doc == null) return;
      final snap = await doc.get();
      if (_email != email) return;
      final local = usage.value ?? _readLocal(email);
      final merged = snap.exists
          ? local.merge(Usage.fromJson(snap.data()!))
          : local;
      usage.value = merged;
      await _writeLocal(email, merged);
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
        // Another device may have synced too: add to the server's count,
        // but never report less than this phone has seen.
        final serverRows = remote == null || remote.month != u.month
            ? 0
            : remote.rowsSynced + added;
        final rows = serverRows > u.rowsSynced ? serverRows : u.rowsSynced;
        tx.set(doc, {
          ..._remoteFields(u.copyWith(rowsSynced: rows)),
          if (remote?.trialStartedAt != null)
            'trialStartedAt': Timestamp.fromDate(remote!.trialStartedAt!),
        }, SetOptions(merge: true));
      });
    } catch (e) {
      debugPrint('Usage push failed: $e');
    }
  }

  Map<String, Object?> _remoteFields(Usage u) => {
    'email': _email,
    'month': u.month,
    'rowsSynced': u.rowsSynced,
    if (u.trialStartedAt != null)
      'trialStartedAt': Timestamp.fromDate(u.trialStartedAt!),
    'updatedAt': FieldValue.serverTimestamp(),
  };
}
