// Scan Session data models
// Immutable with copyWith() — state updates go through ScanSessionService.

enum SessionColumnType {
  scan, // Camera scans into this cell
  manual, // User types (optional, doesn't block scan flow)
  timestamp, // Auto-filled with DateTime.now()
  increment, // Auto-numbered: 1, 2, 3…
  fixed, // Same value every row
  location, // Auto-filled with GPS lat,lng at scan time
}

enum SessionDestination { localCsv, localXlsx, googleSheets }

class SessionColumn {
  final String name;
  final SessionColumnType type;
  final String? fixedValue;
  final String? defaultValue; // pre-fills the field in confirmation sheet
  final bool isNumeric; // shows stepper (– N +) instead of TextField
  final int stepSize; // stepper increment, defaults to 1

  const SessionColumn({
    required this.name,
    required this.type,
    this.fixedValue,
    this.defaultValue,
    this.isNumeric = false,
    this.stepSize = 1,
  });

  SessionColumn copyWith({
    String? name,
    SessionColumnType? type,
    String? fixedValue,
    String? defaultValue,
    bool? isNumeric,
    int? stepSize,
  }) {
    return SessionColumn(
      name: name ?? this.name,
      type: type ?? this.type,
      fixedValue: fixedValue ?? this.fixedValue,
      defaultValue: defaultValue ?? this.defaultValue,
      isNumeric: isNumeric ?? this.isNumeric,
      stepSize: stepSize ?? this.stepSize,
    );
  }

  Map<String, dynamic> toMap() => {
    'name': name,
    'type': type.name,
    'fixedValue': fixedValue,
    'defaultValue': defaultValue,
    'isNumeric': isNumeric,
    'stepSize': stepSize,
  };

  factory SessionColumn.fromMap(Map map) => SessionColumn(
    name: map['name'] as String,
    type: SessionColumnType.values.firstWhere(
      (e) => e.name == map['type'],
      orElse: () => SessionColumnType.scan,
    ),
    fixedValue: map['fixedValue'] as String?,
    defaultValue: map['defaultValue'] as String?,
    isNumeric: map['isNumeric'] as bool? ?? false,
    stepSize: map['stepSize'] as int? ?? 1,
  );
}

class SessionRow {
  final int rowIndex;
  final List<String> values;
  final DateTime scannedAt;
  final String? barcodeFormat; // e.g. 'qr', 'ean13', 'code128'

  const SessionRow({
    required this.rowIndex,
    required this.values,
    required this.scannedAt,
    this.barcodeFormat,
  });

  SessionRow copyWith({
    int? rowIndex,
    List<String>? values,
    DateTime? scannedAt,
    String? barcodeFormat,
  }) {
    return SessionRow(
      rowIndex: rowIndex ?? this.rowIndex,
      values: values ?? this.values,
      scannedAt: scannedAt ?? this.scannedAt,
      barcodeFormat: barcodeFormat ?? this.barcodeFormat,
    );
  }

  Map<String, dynamic> toMap() => {
    'rowIndex': rowIndex,
    'values': values,
    'scannedAt': scannedAt.toIso8601String(),
    'barcodeFormat': barcodeFormat,
  };

  factory SessionRow.fromMap(Map map) => SessionRow(
    rowIndex: map['rowIndex'] as int,
    values: List<String>.from(map['values'] as List),
    scannedAt: DateTime.parse(map['scannedAt'] as String),
    barcodeFormat: map['barcodeFormat'] as String?,
  );
}

class ScanSession {
  final String id;
  final String name;
  final List<SessionColumn> columns;
  final DateTime createdAt;
  final DateTime? completedAt;
  final bool isActive;
  final bool warnDuplicates;
  final bool showScanConfirmation;
  final SessionDestination destination;
  final String? templateId;
  final String? spreadsheetId;
  final String? sheetName;

  const ScanSession({
    required this.id,
    required this.name,
    required this.columns,
    required this.createdAt,
    this.completedAt,
    this.isActive = true,
    this.warnDuplicates = false,
    this.showScanConfirmation = false,
    this.destination = SessionDestination.localCsv,
    this.templateId,
    this.spreadsheetId,
    this.sheetName,
  });

  static const int maxColumns = 10;

  int get columnCount => columns.length;

  List<int> get scanColumnIndices => [
    for (int i = 0; i < columns.length; i++)
      if (columns[i].type == SessionColumnType.scan) i,
  ];

  List<int> get manualColumnIndices => [
    for (int i = 0; i < columns.length; i++)
      if (columns[i].type == SessionColumnType.manual) i,
  ];

  /// Builds a row synchronously. For location columns, inserts a placeholder
  /// ('…') that must be replaced by calling LocationService asynchronously
  /// before saving the row. Use [buildRowAsync] when possible.
  SessionRow buildEmptyRow(int rowIndex) {
    final values = <String>[];
    for (final col in columns) {
      switch (col.type) {
        case SessionColumnType.timestamp:
          values.add(DateTime.now().toLocal().toString().substring(0, 19));
        case SessionColumnType.increment:
          values.add('${rowIndex + 1}');
        case SessionColumnType.fixed:
          values.add(col.fixedValue ?? '');
        case SessionColumnType.location:
          // Placeholder — caller must patch this via LocationService
          values.add('…');
        case SessionColumnType.scan:
        case SessionColumnType.manual:
          values.add('');
      }
    }
    return SessionRow(
      rowIndex: rowIndex,
      values: values,
      scannedAt: DateTime.now(),
    );
  }

  ScanSession copyWith({
    String? id,
    String? name,
    List<SessionColumn>? columns,
    DateTime? createdAt,
    DateTime? completedAt,
    bool? isActive,
    bool? warnDuplicates,
    bool? showScanConfirmation,
    SessionDestination? destination,
    String? templateId,
    String? spreadsheetId,
    String? sheetName,
  }) {
    return ScanSession(
      id: id ?? this.id,
      name: name ?? this.name,
      columns: columns ?? this.columns,
      createdAt: createdAt ?? this.createdAt,
      completedAt: completedAt ?? this.completedAt,
      isActive: isActive ?? this.isActive,
      warnDuplicates: warnDuplicates ?? this.warnDuplicates,
      showScanConfirmation: showScanConfirmation ?? this.showScanConfirmation,
      destination: destination ?? this.destination,
      templateId: templateId ?? this.templateId,
      spreadsheetId: spreadsheetId ?? this.spreadsheetId,
      sheetName: sheetName ?? this.sheetName,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'columns': columns.map((c) => c.toMap()).toList(),
    'createdAt': createdAt.toIso8601String(),
    'completedAt': completedAt?.toIso8601String(),
    'isActive': isActive,
    'warnDuplicates': warnDuplicates,
    'showScanConfirmation': showScanConfirmation,
    'destination': destination.name,
    'templateId': templateId,
    'spreadsheetId': spreadsheetId,
    'sheetName': sheetName,
  };

  factory ScanSession.fromMap(Map map) => ScanSession(
    id: map['id'] as String,
    name: map['name'] as String,
    columns: (map['columns'] as List)
        .map((c) => SessionColumn.fromMap(c as Map))
        .toList(),
    createdAt: DateTime.parse(map['createdAt'] as String),
    completedAt: map['completedAt'] != null
        ? DateTime.parse(map['completedAt'] as String)
        : null,
    isActive: map['isActive'] as bool? ?? false,
    warnDuplicates: map['warnDuplicates'] as bool? ?? false,
    showScanConfirmation: map['showScanConfirmation'] as bool? ?? false,
    destination: SessionDestination.values.firstWhere(
      (e) => e.name == map['destination'],
      orElse: () => SessionDestination.localCsv,
    ),
    templateId: map['templateId'] as String?,
    spreadsheetId: map['spreadsheetId'] as String?,
    sheetName: map['sheetName'] as String?,
  );

  List<List<String>> toTableData(List<SessionRow> rows) {
    final header = columns.map((c) => c.name).toList();
    final data = rows.map((r) => r.values).toList();
    return [header, ...data];
  }
}
