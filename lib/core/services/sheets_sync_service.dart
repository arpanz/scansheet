import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../../features/scan/models/scan_session.dart';
import '../models/sync_queue_item.dart';
import 'google_sheets_service.dart';
import 'scan_session_service.dart';
import 'sheet_cells.dart';
import 'sync_queue_service.dart';

/// Drains the [SyncQueueService] into Google Sheets so rows appear in the
/// sheet seconds after they are scanned.
///
/// - Bursts of scans are debounced into one append request per worksheet.
/// - The header row is written the first time a session reaches an empty tab.
/// - Each row remembers its sheet row number, so edits (Qty merge,
///   corrections) overwrite it and undo blanks it. The row is checked
///   first, and found again if people sorted or inserted rows in the sheet.
/// - Codes go in as text, so leading zeros and long numbers survive.
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

  /// Spreadsheets that were deleted or lost access (404/403). Rows for them
  /// stay queued until the user picks a new home for them.
  final ValueNotifier<Set<String>> missingSheets = ValueNotifier(const {});

  /// Google rejected our credentials; the user must sign in again.
  final ValueNotifier<bool> authExpired = ValueNotifier(false);

  /// Connectivity, for the offline banner.
  final ValueNotifier<bool> online = ValueNotifier(true);

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
    online.value = _online;
    _connectivitySub = Connectivity().onConnectivityChanged.listen((result) {
      _online = _isOnline(result);
      online.value = _online;
      if (_online) syncSoon();
    });
    SyncQueueService.stats.addListener(_onQueueChanged);
    _sheets.signedInNotifier.addListener(_onSignInChanged);
    syncSoon();
  }

  void _onSignInChanged() {
    if (_sheets.isSignedIn) authExpired.value = false;
    syncSoon();
  }

  /// The user moved a sheet's rows elsewhere; stop flagging it.
  void forgetMissing(String spreadsheetId) {
    missingSheets.value = {...missingSheets.value}..remove(spreadsheetId);
  }

  void dispose() {
    _connectivitySub?.cancel();
    _debounceTimer?.cancel();
    _retryTimer?.cancel();
    SyncQueueService.stats.removeListener(_onQueueChanged);
    _sheets.signedInNotifier.removeListener(_onSignInChanged);
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
    final missing = missingSheets.value;
    final ready = SyncQueueService.getPendingItems()
        .where(
          (i) =>
              i.destination == SyncDestination.googleSheets &&
              (i.spreadsheetId?.isNotEmpty ?? false) &&
              !missing.contains(i.spreadsheetId),
        )
        .toList();
    if (ready.isEmpty) return;

    final appends = <String, List<SyncQueueItem>>{};
    final inPlace = <String, List<SyncQueueItem>>{};
    for (final item in ready) {
      (item.op == SyncOp.append ? appends : inPlace)
          .putIfAbsent(
            '${item.spreadsheetId}|${item.sheetName ?? ''}',
            () => [],
          )
          .add(item);
    }
    for (final group in inPlace.values) {
      await _syncInPlace(group);
    }
    // Rows past the free plan's monthly allowance never reach the queue
    // (UsageService locks them), so everything here may go.
    for (final rows in appends.values) {
      for (var i = 0; i < rows.length; i += _maxBatch) {
        final end = (i + _maxBatch).clamp(0, rows.length);
        await _appendGroup(rows.sublist(i, end));
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
      final rows = [?header, for (final item in items) _forSheet(item)];
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

  /// Edits and deletions of rows already in one tab. Each row is checked
  /// where we left it before anything is written; if people sorted,
  /// inserted or deleted rows in the sheet since, it's found again by its
  /// scan cells, so an edit never lands on someone else's row.
  Future<void> _syncInPlace(List<SyncQueueItem> items) async {
    final id = items.first.spreadsheetId!;
    final String tab;
    final Map<String, int?> rows;
    try {
      tab = await _tabFor(id, items.first.sheetName);
      await _markSyncing(items);
      rows = await _locate(id, tab, items);
    } catch (e) {
      for (final item in items) {
        await _fail(item, e);
      }
      return;
    }
    for (final item in items) {
      final row = rows[item.id];
      try {
        if (item.sheetRow != null && row == null) {
          await _leftSheet(item, tab);
          continue;
        }
        if (row != null) {
          if (item.op == SyncOp.clear) {
            await _sheets.clearRow(id, tab, row);
          } else {
            await _sheets.updateRow(id, tab, row, _forSheet(item));
          }
        }
        await _finish(item, tab: tab, sheetRow: row);
        lastError.value = null;
      } catch (e) {
        await _fail(item, e);
      }
    }
  }

  /// Where each row is in the tab now, by item id; null if it's gone.
  /// One read checks every remembered row; the whole tab is read only when
  /// one of them has moved.
  Future<Map<String, int?>> _locate(
    String spreadsheetId,
    String tab,
    List<SyncQueueItem> items,
  ) async {
    final found = <String, int?>{};
    final placed = [
      for (final i in items)
        if (i.sheetRow != null) i,
    ];
    if (placed.isEmpty) return found;
    final current = await _sheets.readRows(spreadsheetId, tab, [
      for (final i in placed) i.sheetRow!,
    ]);
    final moved = <SyncQueueItem>[];
    for (final (k, item) in placed.indexed) {
      if (SheetCells.rowMatches(_sentOf(item), current[k], _identity(item))) {
        found[item.id] = item.sheetRow;
      } else {
        moved.add(item);
      }
    }
    if (moved.isEmpty) return found;
    final table = await _sheets.readTabRaw(spreadsheetId, tab);
    final taken = {...found.values.whereType<int>()};
    for (final item in moved) {
      final row = SheetCells.locate(
        sent: _sentOf(item),
        table: table,
        identity: _identity(item),
        near: item.sheetRow!,
        taken: taken,
      );
      if (row != null) taken.add(row);
      found[item.id] = row;
    }
    return found;
  }

  /// The row was deleted in the sheet. A deletion here has nothing left to
  /// blank; an edit goes back in as a new row, so the sheet still matches
  /// the phone.
  Future<void> _leftSheet(SyncQueueItem item, String tab) async {
    final current = SyncQueueService.get(item.id);
    if (current == null) return;
    if (current.op == SyncOp.clear) {
      await SyncQueueService.put(
        current.copyWith(
          status: SyncStatus.synced,
          dropSheetRow: true,
          sheetName: tab,
          lastAttemptAt: DateTime.now(),
        ),
      );
      return;
    }
    await SyncQueueService.put(
      current.copyWith(
        op: SyncOp.append,
        dropSheetRow: true,
        status: SyncStatus.pending,
      ),
    );
    _runAgain = true;
  }

  /// How the row looks in the sheet, as far as we know.
  static List<String> _sentOf(SyncQueueItem item) =>
      item.sentData ?? item.rowData;

  /// Cells that tell one row from another: the scans, the time and the
  /// row number. Edits rarely touch them. Without the session, every cell.
  static List<int> _identity(SyncQueueItem item) {
    final columns = ScanSessionService.getSession(item.sessionId)?.columns;
    if (columns == null) {
      return [for (var i = 0; i < item.rowData.length; i++) i];
    }
    return [
      for (final (i, c) in columns.indexed)
        if (const {
          SessionColumnType.scan,
          SessionColumnType.timestamp,
          SessionColumnType.increment,
        }.contains(c.type))
          i,
    ];
  }

  /// The row's cells as sent, with codes kept as text.
  static List<String> _forSheet(SyncQueueItem item) {
    final columns = ScanSessionService.getSession(item.sessionId)?.columns;
    return SheetCells.forSheet(item.rowData, {
      for (final (i, c) in columns?.indexed ?? const <(int, SessionColumn)>[])
        if (const {
          SessionColumnType.scan,
          SessionColumnType.readText,
          SessionColumnType.fromList,
        }.contains(c.type))
          i,
    });
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
            sentData: sent.rowData,
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
        sentData: sent.op == SyncOp.clear || sheetRow == null
            ? null
            : sent.rowData,
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
    _classify(lastError.value!, item.spreadsheetId);
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

  void _classify(String message, String? spreadsheetId) {
    final m = message.toLowerCase();
    if (m.contains('401') ||
        m.contains('unauthenticated') ||
        m.contains('invalid_grant') ||
        m.contains('not signed in')) {
      authExpired.value = true;
    } else if (spreadsheetId != null &&
        (m.contains('404') ||
            m.contains('403') ||
            m.contains('not found') ||
            m.contains('permission'))) {
      missingSheets.value = {...missingSheets.value, spreadsheetId};
    }
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
    return session?.headerNames;
  }

  void _scheduleRetry() {
    _retryTimer?.cancel();
    final next = SyncQueueService.nextRetryAt();
    if (next == null) return;
    final wait = next.difference(DateTime.now()) + const Duration(seconds: 1);
    _retryTimer = Timer(wait.isNegative ? Duration.zero : wait, flush);
  }
}
