// Scan Session data models
// Immutable with copyWith() — state updates go through ScanSessionService.

enum SessionColumnType {
  scan,       // Camera scans into this cell
  manual,     // User types (optional, doesn't block scan flow)
  timestamp,  // Auto-filled with DateTime.now()
  increment,  // Auto-numbered: 1, 2, 3…
  fixed,      // Same value every row
}

class SessionColumn {
  final String name;
  final SessionColumnType type;
  final String? fixedValue; // only relevant when type == fixed

  const SessionColumn({
    required this.name,
    required this.type,
    this.fixedValue,
  });

  SessionColumn copyWith({
    String? name,
    SessionColumnType? type,
    String? fixedValue,
  }) {
    return SessionColumn(
      name: name ?? this.name,
      type: type ?? this.type,
      fixedValue: fixedValue ?? this.fixedValue,
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'type': type.name,
        'fixedValue': fixedValue,
      };

  factory SessionColumn.fromMap(Map map) => SessionColumn(
        name: map['name'] as String,
        type: SessionColumnType.values.firstWhere(
          (e) => e.name == map['type'],
          orElse: () => SessionColumnType.scan,
        ),
        fixedValue: map['fixedValue'] as String?,
      );
}

class SessionRow {
  final int rowIndex;
  final List<String> values; // values[i] maps to session.columns[i]
  final DateTime scannedAt;

  const SessionRow({
    required this.rowIndex,
    required this.values,
    required this.scannedAt,
  });

  SessionRow copyWith({
    int? rowIndex,
    List<String>? values,
    DateTime? scannedAt,
  }) {
    return SessionRow(
      rowIndex: rowIndex ?? this.rowIndex,
      values: values ?? this.values,
      scannedAt: scannedAt ?? this.scannedAt,
    );
  }

  Map<String, dynamic> toMap() => {
        'rowIndex': rowIndex,
        'values': values,
        'scannedAt': scannedAt.toIso8601String(),
      };

  factory SessionRow.fromMap(Map map) => SessionRow(
        rowIndex: map['rowIndex'] as int,
        values: List<String>.from(map['values'] as List),
        scannedAt: DateTime.parse(map['scannedAt'] as String),
      );
}

class ScanSession {
  final String id;
  final String name;
  final List<SessionColumn> columns;
  final DateTime createdAt;
  final DateTime? completedAt;
  final bool isActive;
  final bool warnDuplicates; // warn-only, not hard-block

  const ScanSession({
    required this.id,
    required this.name,
    required this.columns,
    required this.createdAt,
    this.completedAt,
    this.isActive = true,
    this.warnDuplicates = false,
  });

  /// Max columns allowed per session.
  static const int maxColumns = 10;

  int get columnCount => columns.length;

  /// Scan-type columns only — these drive the camera scan loop.
  List<int> get scanColumnIndices => [
        for (int i = 0; i < columns.length; i++)
          if (columns[i].type == SessionColumnType.scan) i,
      ];

  /// Build a new row with auto-filled values for timestamp/increment/fixed columns.
  /// Scan and manual columns are left empty — filled during scanning.
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
  }) {
    return ScanSession(
      id: id ?? this.id,
      name: name ?? this.name,
      columns: columns ?? this.columns,
      createdAt: createdAt ?? this.createdAt,
      completedAt: completedAt ?? this.completedAt,
      isActive: isActive ?? this.isActive,
      warnDuplicates: warnDuplicates ?? this.warnDuplicates,
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
      );

  /// Returns header row + data rows for CSV/Excel export.
  /// [rows] must be passed in (loaded separately from the rows Hive box).
  List<List<String>> toTableData(List<SessionRow> rows) {
    final header = columns.map((c) => c.name).toList();
    final data = rows.map((r) => r.values).toList();
    return [header, ...data];
  }
}
