// Offline sync queue item — stored as plain Map in Hive (no TypeAdapter needed).

enum SyncStatus { pending, syncing, failed, synced }

enum SyncDestination { googleSheets, localCsv, localXlsx }

/// What the next sync attempt must do with this row.
/// append: not in the sheet yet · update: overwrite [SyncQueueItem.sheetRow]
/// · clear: row was deleted locally, blank it in the sheet.
enum SyncOp { append, update, clear }

class SyncQueueItem {
  final String id;
  final String sessionId;
  final int rowIndex;
  final List<String> rowData;
  final SyncDestination destination;
  final String? spreadsheetId;
  final String? sheetName;
  final SyncOp op;

  /// 1-based row in the Google Sheet once appended.
  final int? sheetRow;
  SyncStatus status;
  final DateTime createdAt;
  DateTime? lastAttemptAt;
  String? errorMessage;
  int attemptCount;

  SyncQueueItem({
    required this.id,
    required this.sessionId,
    required this.rowIndex,
    required this.rowData,
    required this.destination,
    this.spreadsheetId,
    this.sheetName,
    this.op = SyncOp.append,
    this.sheetRow,
    this.status = SyncStatus.pending,
    required this.createdAt,
    this.lastAttemptAt,
    this.errorMessage,
    this.attemptCount = 0,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'sessionId': sessionId,
    'rowIndex': rowIndex,
    'rowData': rowData,
    'destination': destination.name,
    'spreadsheetId': spreadsheetId,
    'sheetName': sheetName,
    'op': op.name,
    'sheetRow': sheetRow,
    'status': status.name,
    'createdAt': createdAt.toIso8601String(),
    'lastAttemptAt': lastAttemptAt?.toIso8601String(),
    'errorMessage': errorMessage,
    'attemptCount': attemptCount,
  };

  factory SyncQueueItem.fromMap(Map map) => SyncQueueItem(
    id: map['id'] as String,
    sessionId: map['sessionId'] as String,
    rowIndex: map['rowIndex'] as int,
    rowData: List<String>.from(map['rowData'] as List),
    destination: SyncDestination.values.firstWhere(
      (e) => e.name == map['destination'],
      orElse: () => SyncDestination.googleSheets,
    ),
    spreadsheetId: map['spreadsheetId'] as String?,
    sheetName: map['sheetName'] as String?,
    op: SyncOp.values.firstWhere(
      (e) => e.name == map['op'],
      orElse: () => SyncOp.append,
    ),
    sheetRow: map['sheetRow'] as int?,
    status: SyncStatus.values.firstWhere(
      (e) => e.name == map['status'],
      orElse: () => SyncStatus.pending,
    ),
    createdAt: DateTime.parse(map['createdAt'] as String),
    lastAttemptAt: map['lastAttemptAt'] != null
        ? DateTime.parse(map['lastAttemptAt'] as String)
        : null,
    errorMessage: map['errorMessage'] as String?,
    attemptCount: map['attemptCount'] as int? ?? 0,
  );

  SyncQueueItem copyWith({
    List<String>? rowData,
    SyncOp? op,
    int? sheetRow,
    String? sheetName,
    SyncStatus? status,
    DateTime? lastAttemptAt,
    String? errorMessage,
    int? attemptCount,
  }) => SyncQueueItem(
    id: id,
    sessionId: sessionId,
    rowIndex: rowIndex,
    rowData: rowData ?? this.rowData,
    destination: destination,
    spreadsheetId: spreadsheetId,
    sheetName: sheetName ?? this.sheetName,
    op: op ?? this.op,
    sheetRow: sheetRow ?? this.sheetRow,
    status: status ?? this.status,
    createdAt: createdAt,
    lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
    errorMessage: errorMessage ?? this.errorMessage,
    attemptCount: attemptCount ?? this.attemptCount,
  );
}

class SyncQueueStats {
  final int pendingCount;
  final int failedCount;
  final int syncedCount;
  final int totalCount;
  final DateTime? lastSyncAt;

  const SyncQueueStats({
    required this.pendingCount,
    required this.failedCount,
    required this.syncedCount,
    required this.totalCount,
    this.lastSyncAt,
  });

  int get totalSizeEstimateBytes => totalCount * 256; // rough estimate
}
