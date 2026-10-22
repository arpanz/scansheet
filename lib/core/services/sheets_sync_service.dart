import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../models/sync_queue_item.dart';
import 'google_sheets_service.dart';
import 'scan_session_service.dart';
import 'sync_queue_service.dart';

/// Drains the [SyncQueueService] into Google Sheets so rows appear in the
/// sheet seconds after they are scanned.
///
/// - Bursts of scans are debounced into one append request per worksheet.
/// - The header row is written the first time a session reaches an empty tab.
/// - Each row remembers its sheet row number, so edits (Qty merge,
///   corrections) overwrite it and undo blanks it.
/// - Offline or failed rows stay queued and retry with backoff, on
///   reconnect, on sign-in and on app resume.
class SheetsSyncService {
  SheetsSyncService._();
  static final SheetsSyncService instance = SheetsSyncService._();

  static const _debounce = Duration(milliseconds: 600);
  static const _maxBatch = 200;

  final _sheets = GoogleSheetsService.instance;

  /// Last sync error shown in UI states; null once a sync succeeds.
  final ValueNotifier<String?> lastError = ValueNotifier(null);

  final _firstTabCache = <String, String>{};
  final _headerReady = <String>{};
  Timer? _debounceTimer;
  Timer? _retryTimer;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool _online = true;
  bool _running = false;
  bool _runAgain = false;

  bool get isOnline => _online;

  Future<void> start() async {
    _online = _isOnline(await Connectivity().checkConnectivity());
    _connectivitySub = Connectivity().onConnectivityChanged.listen((result) {
      _online = _isOnline(result);
      if (_online) syncSoon();
    });
    SyncQueueService.stats.addListener(_onQueueChanged);
    _sheets.signedInNotifier.addListener(syncSoon);
    syncSoon();
  }

  void dispose() {
    _connectivitySub?.cancel();
    _debounceTimer?.cancel();
    _retryTimer?.cancel();
    SyncQueueService.stats.removeListener(_onQueueChanged);
    _sheets.signedInNotifier.removeListener(syncSoon);
  }

  /// Schedule a sync shortly, coalescing rapid calls.
  void syncSoon() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounce, flush);
  }

  /// Retry failed rows now, ignoring backoff.
  Future<void> retryNow() async {
    await SyncQueueService.retryFailed();
    await flush();
  }

  Future<void> flush() async {
    if (_running) {
      _runAgain = true;
      return;
    }
    if (!_sheets.isSignedIn || !_online) return;
    _running = true;
    try {
      do {
        _runAgain = false;
        await _runOnce();
      } while (_runAgain);
    } finally {
      _running = false;
      _scheduleRetry();
    }
  }

  void _onQueueChanged() {
    if (SyncQueueService.stats.value.pendingCount > 0) syncSoon();
  }

  static bool _isOnline(List<ConnectivityResult> result) =>
      !result.contains(ConnectivityResult.none);

  Future<void> _runOnce() async {
    final ready = SyncQueueService.getPendingItems()
        .where(
          (i) =>
              i.destination == SyncDestination.googleSheets &&
              (i.spreadsheetId?.isNotEmpty ?? false),
        )
        .toList();
    if (ready.isEmpty) return;

    final appends = <String, List<SyncQueueItem>>{};
    for (final item in ready) {
      if (item.op == SyncOp.append) {
        appends
            .putIfAbsent(
              '${item.spreadsheetId}|${item.sheetName ?? ''}',
              () => [],
            )
            .add(item);
      } else {
        await _syncInPlace(item);
      }
    }
    for (final group in appends.values) {
      for (var i = 0; i < group.length; i += _maxBatch) {
        final end = (i + _maxBatch).clamp(0, group.length);
        await _appendGroup(group.sublist(i, end));
      }
    }
  }

  Future<void> _appendGroup(List<SyncQueueItem> items) async {
    final first = items.first;
    final id = first.spreadsheetId!;
    try {
      final tab = await _tabFor(id, first.sheetName);
      await _markSyncing(items);
      final header = await _headerIfNeeded(id, tab, first.sessionId);
      final rows = [?header, for (final item in items) item.rowData];
      final start = await _sheets.appendRows(id, tab, rows);
      _headerReady.add('$id|$tab');
      final dataStart = start == null
          ? null
          : (header != null ? start + 1 : start);
      for (var k = 0; k < items.length; k++) {
        await _finish(
          items[k],
          tab: tab,
          sheetRow: dataStart == null ? null : dataStart + k,
        );
      }
      lastError.value = null;
    } catch (e) {
      for (final item in items) {
        await _fail(item, e);
      }
    }
  }

  Future<void> _syncInPlace(SyncQueueItem item) async {
    final id = item.spreadsheetId!;
    final row = item.sheetRow;
    try {
      final tab = await _tabFor(id, item.sheetName);
      await _markSyncing([item]);
      if (row != null) {
        if (item.op == SyncOp.clear) {
          await _sheets.clearRow(id, tab, row);
        } else {
          await _sheets.updateRow(id, tab, row, item.rowData);
        }
      }
      await _finish(item, tab: tab, sheetRow: row);
      lastError.value = null;
    } catch (e) {
      await _fail(item, e);
    }
  }

  /// Records a successful send. If the row was edited, deleted or reused
  /// while the request was in flight, it stays pending for another pass.
  Future<void> _finish(
    SyncQueueItem sent, {
    required String tab,
    required int? sheetRow,
  }) async {
    final current = SyncQueueService.get(sent.id);
    if (current == null) {
      // Deleted locally mid-flight after it already reached the sheet.
      if (sheetRow != null && sent.op != SyncOp.clear) {
        await SyncQueueService.put(
          sent.copyWith(
            op: SyncOp.clear,
            sheetRow: sheetRow,
            sheetName: tab,
            status: SyncStatus.pending,
          ),
        );
      }
      return;
    }
    final unchanged =
        current.op == sent.op && listEquals(current.rowData, sent.rowData);
    await SyncQueueService.put(
      current.copyWith(
        sheetRow: sheetRow,
        sheetName: tab,
        op: unchanged || current.op != SyncOp.append
            ? current.op
            : SyncOp.update,
        status: unchanged ? SyncStatus.synced : SyncStatus.pending,
        lastAttemptAt: DateTime.now(),
      ),
    );
  }

  Future<void> _fail(SyncQueueItem item, Object error) async {
    debugPrint('Sheets sync failed for ${item.id}: $error');
    lastError.value = error is GSheetsException ? error.message : '$error';
    final current = SyncQueueService.get(item.id);
    if (current == null) return;
    await SyncQueueService.put(
      current.copyWith(
        status: SyncStatus.failed,
        lastAttemptAt: DateTime.now(),
        attemptCount: current.attemptCount + 1,
        errorMessage: lastError.value,
      ),
    );
  }

  Future<void> _markSyncing(List<SyncQueueItem> items) async {
    for (final item in items) {
      await SyncQueueService.put(item.copyWith(status: SyncStatus.syncing));
    }
  }

  Future<String> _tabFor(String spreadsheetId, String? sheetName) async {
    if (sheetName != null && sheetName.isNotEmpty) return sheetName;
    final cached = _firstTabCache[spreadsheetId];
    if (cached != null) return cached;
    final tabs = await _sheets.getWorksheets(spreadsheetId);
    return _firstTabCache[spreadsheetId] = tabs.isEmpty ? 'Sheet1' : tabs.first;
  }

  /// The session's column names when the tab has no header row yet.
  Future<List<String>?> _headerIfNeeded(
    String spreadsheetId,
    String tab,
    String sessionId,
  ) async {
    if (_headerReady.contains('$spreadsheetId|$tab')) return null;
    final existing = await _sheets.getSheetHeaders(spreadsheetId, tab);
    if (existing.isNotEmpty) {
      _headerReady.add('$spreadsheetId|$tab');
      return null;
    }
    final session = ScanSessionService.getSession(sessionId);
    return session?.columns.map((c) => c.name).toList();
  }

  void _scheduleRetry() {
    _retryTimer?.cancel();
    final next = SyncQueueService.nextRetryAt();
    if (next == null) return;
    final wait = next.difference(DateTime.now()) + const Duration(seconds: 1);
    _retryTimer = Timer(wait.isNegative ? Duration.zero : wait, flush);
  }
}
