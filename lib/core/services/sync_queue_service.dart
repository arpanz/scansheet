import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/sync_queue_item.dart';

/// Offline-first sync queue.
/// Stores [SyncQueueItem]s as plain Maps in a dedicated Hive box.
/// Exposes a [ValueNotifier<SyncQueueStats>] for reactive UI updates.
class SyncQueueService {
  static const _boxName = 'sync_queue';
  static Box? _box;

  static final ValueNotifier<SyncQueueStats> stats = ValueNotifier(
    const SyncQueueStats(
      pendingCount: 0,
      failedCount: 0,
      syncedCount: 0,
      totalCount: 0,
    ),
  );

  // Whether a processQueue() run is in progress.
  static bool _isSyncing = false;

  // Backoff durations indexed by attemptCount (capped at last entry).
  static const _backoffDurations = [
    Duration(seconds: 5),
    Duration(seconds: 15),
    Duration(seconds: 60),
    Duration(minutes: 5),
    Duration(minutes: 15),
  ];

  static Box get _safeBox {
    assert(_box != null, 'Call SyncQueueService.init() before use.');
    return _box!;
  }

  // ───────────────────────────────────────────────
  // Init
  // ───────────────────────────────────────────────

  static Future<void> init() async {
    _box = await Hive.openBox(_boxName);
    _refreshStats();
  }

  // ───────────────────────────────────────────────
  // Public API
  // ───────────────────────────────────────────────

  /// Add a new row to the sync queue.
  static Future<void> enqueue(SyncQueueItem item) async {
    await _safeBox.put(item.id, item.toMap());
    _refreshStats();
  }

  /// Returns all items sorted by createdAt ascending.
  static List<SyncQueueItem> getAll() {
    final items = <SyncQueueItem>[];
    for (final key in _safeBox.keys) {
      final raw = _safeBox.get(key);
      if (raw == null) continue;
      try {
        items.add(SyncQueueItem.fromMap(Map<String, dynamic>.from(raw as Map)));
      } catch (_) {}
    }
    items.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return items;
  }

  /// All pending or failed items that are ready to retry.
  static List<SyncQueueItem> getPendingItems() {
    final now = DateTime.now();
    return getAll().where((item) {
      if (item.status == SyncStatus.synced) return false;
      if (item.status == SyncStatus.syncing) return false;
      if (item.status == SyncStatus.failed) {
        // Exponential backoff check.
        final delay = _backoffDurations[
            item.attemptCount.clamp(0, _backoffDurations.length - 1)];
        final nextRetry =
            (item.lastAttemptAt ?? item.createdAt).add(delay);
        return now.isAfter(nextRetry);
      }
      return true; // pending
    }).toList();
  }

  /// Process the queue. Pass a handler that does the actual API call.
  /// [syncHandler] returns true on success, false on failure.
  static Future<void> processQueue(
    Future<bool> Function(SyncQueueItem item) syncHandler,
  ) async {
    if (_isSyncing) return;
    _isSyncing = true;
    try {
      final pending = getPendingItems();
      for (final item in pending) {
        // Mark as syncing.
        final syncing = item.copyWith(status: SyncStatus.syncing);
        await _safeBox.put(syncing.id, syncing.toMap());

        final success = await syncHandler(item);
        final now = DateTime.now();

        if (success) {
          final done = item.copyWith(
            status: SyncStatus.synced,
            lastAttemptAt: now,
            errorMessage: null,
            attemptCount: item.attemptCount + 1,
          );
          await _safeBox.put(done.id, done.toMap());
        } else {
          final failed = item.copyWith(
            status: SyncStatus.failed,
            lastAttemptAt: now,
            attemptCount: item.attemptCount + 1,
          );
          await _safeBox.put(failed.id, failed.toMap());
        }
        _refreshStats();
      }
    } finally {
      _isSyncing = false;
      _refreshStats();
    }
  }

  /// Remove all synced items from the box.
  static Future<void> clearSynced() async {
    final synced = getAll()
        .where((i) => i.status == SyncStatus.synced)
        .map((i) => i.id)
        .toList();
    for (final id in synced) {
      await _safeBox.delete(id);
    }
    _refreshStats();
  }

  /// Remove ALL items for a session (used when a session is deleted).
  static Future<void> clearForSession(String sessionId) async {
    final ids = getAll()
        .where((i) => i.sessionId == sessionId)
        .map((i) => i.id)
        .toList();
    for (final id in ids) {
      await _safeBox.delete(id);
    }
    _refreshStats();
  }

  /// Retry all failed items immediately (reset backoff).
  static Future<void> retryFailed() async {
    final failed =
        getAll().where((i) => i.status == SyncStatus.failed).toList();
    for (final item in failed) {
      final reset = item.copyWith(
        status: SyncStatus.pending,
        attemptCount: 0,
        lastAttemptAt: null,
      );
      await _safeBox.put(reset.id, reset.toMap());
    }
    _refreshStats();
  }

  // ───────────────────────────────────────────────
  // Stats
  // ───────────────────────────────────────────────

  static void _refreshStats() {
    final all = getAll();
    DateTime? lastSync;
    for (final item in all) {
      if (item.status == SyncStatus.synced && item.lastAttemptAt != null) {
        if (lastSync == null ||
            item.lastAttemptAt!.isAfter(lastSync)) {
          lastSync = item.lastAttemptAt;
        }
      }
    }
    stats.value = SyncQueueStats(
      pendingCount:
          all.where((i) => i.status == SyncStatus.pending).length,
      failedCount:
          all.where((i) => i.status == SyncStatus.failed).length,
      syncedCount:
          all.where((i) => i.status == SyncStatus.synced).length,
      totalCount: all.length,
      lastSyncAt: lastSync,
    );
  }
}
