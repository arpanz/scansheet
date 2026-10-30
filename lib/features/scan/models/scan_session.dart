// Scan Session data models
// Immutable with copyWith() — state updates go through ScanSessionService.

enum SessionColumnType {
  scan, // Camera scans into this cell
  manual, // User types (optional, doesn't block scan flow)
  timestamp, // Auto-filled with DateTime.now()
  increment, // Auto-numbered: 1, 2, 3…
  fixed, // Same value every row
  location, // Auto-filled with GPS lat,lng at scan time
  pickList, // One tap from [SessionColumn.choices]; default pre-picked
  productInfo, // Filled from the scanned barcode via product lookup
  readText, // Printed text read on-device (OCR)
  fromList, // One field of the matching row in the sheet's lookup list
}

enum SessionDestination { localCsv, localXlsx, googleSheets }

/// What a Location column records. One reading serves every Location
/// column, so a sheet can have, say, District and PIN code side by side.
enum LocationFormat {
  coordinates('Coordinates', '28.613939,77.209021'),
  address('Full address', 'Janpath, Connaught Place, New Delhi 110001, India'),
  area('Area', 'Connaught Place, New Delhi'),
  district('District', 'New Delhi'),
  state('State', 'Delhi'),
  postalCode('PIN / postcode', '110001'),
  country('Country', 'India');

  final String label;
  final String example;
  const LocationFormat(this.label, this.example);

  /// Every format but coordinates needs a place lookup.
  bool get needsPlace => this != coordinates;
}

/// What happens to a scanned code that isn't on the sheet's list.
enum UnknownCodes {
  ask, // Show Skip / Add anyway
  flag, // Add it, marked On list = No
  skip, // Don't add it
}

class SessionColumn {
  final String name;
  final SessionColumnType type;
  final String? fixedValue;
  final String? defaultValue; // pre-fills the field in confirmation sheet
  final bool isNumeric; // shows stepper (– N +) instead of TextField
  final int stepSize; // stepper increment, defaults to 1
  final List<String> choices; // pick-list options
  final String? labelPrefix; // fixed: codes with this prefix set the value
  final bool askAtStart; // fixed: ask for the value when scanning starts
  final List<String> recentValues; // fixed: newest first, at most 6
  final String? listField; // fromList: list header to fill in
  final LocationFormat locationFormat; // location: what to record

  const SessionColumn({
    required this.name,
    required this.type,
    this.fixedValue,
    this.defaultValue,
    this.isNumeric = false,
    this.stepSize = 1,
    this.choices = const [],
    this.labelPrefix,
    this.askAtStart = false,
    this.recentValues = const [],
    this.listField,
    this.locationFormat = LocationFormat.coordinates,
  });

  SessionColumn copyWith({
    String? name,
    SessionColumnType? type,
    String? fixedValue,
    String? defaultValue,
    bool? isNumeric,
    int? stepSize,
    List<String>? choices,
    String? labelPrefix,
    bool? askAtStart,
    List<String>? recentValues,
    String? listField,
    LocationFormat? locationFormat,
  }) {
    return SessionColumn(
      name: name ?? this.name,
      type: type ?? this.type,
      fixedValue: fixedValue ?? this.fixedValue,
      defaultValue: defaultValue ?? this.defaultValue,
      isNumeric: isNumeric ?? this.isNumeric,
      stepSize: stepSize ?? this.stepSize,
      choices: choices ?? this.choices,
      labelPrefix: labelPrefix ?? this.labelPrefix,
      askAtStart: askAtStart ?? this.askAtStart,
      recentValues: recentValues ?? this.recentValues,
      listField: listField ?? this.listField,
      locationFormat: locationFormat ?? this.locationFormat,
    );
  }

  /// Returns a copy with [fixedValue] set to [value], inserting it at the
  /// front of [recentValues] (deduplicated, capped at 6).
  SessionColumn withValue(String value) {
    final old = (fixedValue?.isNotEmpty ?? false) && fixedValue != value
        ? fixedValue!
        : null;
    final rest = recentValues.where((v) => v != value && v != old);
    final recents = [value, ?old, ...rest].take(6).toList();
    return copyWith(fixedValue: value, recentValues: recents);
  }

  Map<String, dynamic> toMap() => {
    'name': name,
    'type': type.name,
    'fixedValue': fixedValue,
    'defaultValue': defaultValue,
    'isNumeric': isNumeric,
    'stepSize': stepSize,
    'choices': choices,
    'labelPrefix': labelPrefix,
    'askAtStart': askAtStart,
    'recentValues': recentValues,
    'listField': listField,
    'locationFormat': locationFormat.name,
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
    choices: List<String>.from(map['choices'] as List? ?? const []),
    labelPrefix: map['labelPrefix'] as String?,
    askAtStart: map['askAtStart'] as bool? ?? false,
    recentValues: List<String>.from(map['recentValues'] as List? ?? const []),
    listField: map['listField'] as String?,
    locationFormat: LocationFormat.values.firstWhere(
      (e) => e.name == map['locationFormat'],
      orElse: () => LocationFormat.coordinates,
    ),
  );
}

class SessionRow {
  final int rowIndex;
  final List<String> values;
  final DateTime scannedAt;
  final String? barcodeFormat; // e.g. 'qr', 'ean13', 'code128'

  /// Added although the code isn't on the sheet's list ("Add and flag").
  final bool notOnList;

  /// Saved past the free plan's monthly rows: kept on the phone, left out
  /// of Google Sheets and exports until the 1st or an upgrade.
  final bool locked;

  const SessionRow({
    required this.rowIndex,
    required this.values,
    required this.scannedAt,
    this.barcodeFormat,
    this.notOnList = false,
    this.locked = false,
  });

  SessionRow copyWith({
    int? rowIndex,
    List<String>? values,
    DateTime? scannedAt,
    String? barcodeFormat,
    bool? notOnList,
    bool? locked,
  }) {
    return SessionRow(
      rowIndex: rowIndex ?? this.rowIndex,
      values: values ?? this.values,
      scannedAt: scannedAt ?? this.scannedAt,
      barcodeFormat: barcodeFormat ?? this.barcodeFormat,
      notOnList: notOnList ?? this.notOnList,
      locked: locked ?? this.locked,
    );
  }

  Map<String, dynamic> toMap() => {
    'rowIndex': rowIndex,
    'values': values,
    'scannedAt': scannedAt.toIso8601String(),
    'barcodeFormat': barcodeFormat,
    'notOnList': notOnList,
    'locked': locked,
  };

  factory SessionRow.fromMap(Map map) => SessionRow(
    rowIndex: map['rowIndex'] as int,
    values: List<String>.from(map['values'] as List),
    scannedAt: DateTime.parse(map['scannedAt'] as String),
    barcodeFormat: map['barcodeFormat'] as String?,
    notOnList: map['notOnList'] as bool? ?? false,
    locked: map['locked'] as bool? ?? false,
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

  /// Scanning a code that is already in the sheet adds to its Qty cell
  /// instead of creating a new row.
  final bool mergeRepeats;
  final SessionDestination destination;
  final String? templateId;
  final String? spreadsheetId;
  final String? sheetName;

  /// User-picked or template-derived icon key. Null = use generic fallback.
  final String? iconName;

  /// The list scans are checked against. Null = no list.
  final String? lookupListId;
  final UnknownCodes unknownCodes;

  /// Invite code of the team sheet this belongs to (Scan together), or null.
  final String? teamCode;

  const ScanSession({
    required this.id,
    required this.name,
    required this.columns,
    required this.createdAt,
    this.completedAt,
    this.isActive = true,
    this.warnDuplicates = false,
    this.showScanConfirmation = false,
    this.mergeRepeats = false,
    this.destination = SessionDestination.localCsv,
    this.templateId,
    this.spreadsheetId,
    this.sheetName,
    this.iconName,
    this.lookupListId,
    this.unknownCodes = UnknownCodes.ask,
    this.teamCode,
  });

  static const int maxColumns = 10;

  int get columnCount => columns.length;

  /// A code that starts with a Same value column's label prefix sets that
  /// column (prefix stripped, case-insensitive). Null for an ordinary code.
  ({int column, String value})? labelFor(String code) {
    for (var i = 0; i < columns.length; i++) {
      final col = columns[i];
      final prefix = col.labelPrefix ?? '';
      if (col.type != SessionColumnType.fixed || prefix.isEmpty) continue;
      if (!code.toUpperCase().startsWith(prefix.toUpperCase())) continue;
      final value = code.substring(prefix.length).trim();
      return (column: i, value: value.isEmpty ? code : value);
    }
    return null;
  }

  /// Column that "Repeats add to Qty" increments: the first numeric manual
  /// column, else a manual column named Qty/Quantity/Count. -1 if none.
  int get qtyColumnIndex {
    final numeric = columns.indexWhere(
      (c) => c.type == SessionColumnType.manual && c.isNumeric,
    );
    if (numeric >= 0) return numeric;
    const names = {'qty', 'quantity', 'count'};
    return columns.indexWhere(
      (c) =>
          c.type == SessionColumnType.manual &&
          names.contains(c.name.trim().toLowerCase()),
    );
  }

  List<int> get scanColumnIndices => [
    for (int i = 0; i < columns.length; i++)
      if (columns[i].type == SessionColumnType.scan) i,
  ];

  /// Columns the confirm sheet lets the user fill or change.
  List<int> get reviewColumnIndices => [
    for (int i = 0; i < columns.length; i++)
      if (const {
        SessionColumnType.manual,
        SessionColumnType.pickList,
        SessionColumnType.readText,
      }.contains(columns[i].type))
        i,
  ];

  int get productColumnIndex =>
      columns.indexWhere((c) => c.type == SessionColumnType.productInfo);

  List<int> get manualColumnIndices => [
    for (int i = 0; i < columns.length; i++)
      if (columns[i].type == SessionColumnType.manual) i,
  ];

  /// Builds a row synchronously. Location cells start empty; the scanner
  /// fills them when the row is saved, without waiting for a fix.
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
        case SessionColumnType.pickList:
          values.add(
            col.defaultValue ?? (col.choices.isEmpty ? '' : col.choices.first),
          );
        case SessionColumnType.manual:
          // Numbers start at their default so a scan never waits for input.
          values.add(
            col.isNumeric
                ? col.defaultValue ?? '${col.stepSize}'
                : col.defaultValue ?? '',
          );
        case SessionColumnType.scan:
        case SessionColumnType.productInfo:
        case SessionColumnType.readText:
        case SessionColumnType.fromList:
        case SessionColumnType.location:
          values.add('');
      }
    }
    return SessionRow(
      rowIndex: rowIndex,
      values: values,
      scannedAt: DateTime.now(),
    );
  }

  /// Leaves the team sheet: copyWith can't set a field back to null.
  ScanSession withoutTeam() =>
      ScanSession.fromMap({...toMap(), 'teamCode': null});

  ScanSession copyWith({
    String? id,
    String? name,
    List<SessionColumn>? columns,
    DateTime? createdAt,
    DateTime? completedAt,
    bool? isActive,
    bool? warnDuplicates,
    bool? showScanConfirmation,
    bool? mergeRepeats,
    SessionDestination? destination,
    String? templateId,
    String? spreadsheetId,
    String? sheetName,
    String? iconName,
    String? lookupListId,
    UnknownCodes? unknownCodes,
    String? teamCode,
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
      mergeRepeats: mergeRepeats ?? this.mergeRepeats,
      destination: destination ?? this.destination,
      templateId: templateId ?? this.templateId,
      spreadsheetId: spreadsheetId ?? this.spreadsheetId,
      sheetName: sheetName ?? this.sheetName,
      iconName: iconName ?? this.iconName,
      lookupListId: lookupListId ?? this.lookupListId,
      unknownCodes: unknownCodes ?? this.unknownCodes,
      teamCode: teamCode ?? this.teamCode,
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
    'mergeRepeats': mergeRepeats,
    'destination': destination.name,
    'templateId': templateId,
    'spreadsheetId': spreadsheetId,
    'sheetName': sheetName,
    'iconName': iconName,
    'lookupListId': lookupListId,
    'unknownCodes': unknownCodes.name,
    'teamCode': teamCode,
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
    mergeRepeats: map['mergeRepeats'] as bool? ?? false,
    destination: SessionDestination.values.firstWhere(
      (e) => e.name == map['destination'],
      orElse: () => SessionDestination.localCsv,
    ),
    templateId: map['templateId'] as String?,
    spreadsheetId: map['spreadsheetId'] as String?,
    sheetName: map['sheetName'] as String?,
    iconName: map['iconName'] as String?,
    lookupListId: map['lookupListId'] as String?,
    unknownCodes: UnknownCodes.values.firstWhere(
      (e) => e.name == map['unknownCodes'],
      orElse: () => UnknownCodes.ask,
    ),
    teamCode: map['teamCode'] as String?,
  );

  /// A sheet checked against a list that can still add codes not on it
  /// gets a trailing On list column (Yes / No).
  bool get hasOnListColumn =>
      lookupListId != null && unknownCodes != UnknownCodes.skip;

  List<String> get headerNames => [
    for (final c in columns) c.name,
    if (hasOnListColumn) 'On list',
  ];

  /// A row's cells as exported and synced, one per [headerNames].
  List<String> cellsFor(SessionRow row) => [
    for (var i = 0; i < columns.length; i++)
      i < row.values.length ? row.values[i] : '',
    if (hasOnListColumn) row.notOnList ? 'No' : 'Yes',
  ];

  /// Columns whose cells are counts, written as numbers in Excel. Scanned
  /// codes stay text so leading zeros and long digit runs survive.
  Set<int> get numericColumns => {
    for (final (i, c) in columns.indexed)
      if (c.type == SessionColumnType.increment ||
          (c.type == SessionColumnType.manual && c.isNumeric) ||
          i == qtyColumnIndex)
        i,
  };

  List<List<String>> toTableData(List<SessionRow> rows) => [
    headerNames,
    for (final r in rows) cellsFor(r),
  ];
}
