import 'package:hive_flutter/hive_flutter.dart';
import '../../features/scan/models/scan_session.dart';

/// User-saveable session templates stored in Hive.
/// Built-in templates (isBuiltIn == true) cannot be deleted.
class TemplateService {
  static const _boxName = 'session_templates';
  static Box? _box;

  static Box get _safeBox {
    assert(_box != null, 'Call TemplateService.init() before use.');
    return _box!;
  }

  static Future<void> init() async {
    _box = await Hive.openBox(_boxName);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Built-in templates (never persisted to Hive — always generated fresh)
  // ─────────────────────────────────────────────────────────────────────────

  static List<SessionTemplate> getBuiltInTemplates() => [
    SessionTemplate(
      id: 'builtin_inventory',
      name: 'Inventory',
      icon: 'inventory_2_rounded',
      isBuiltIn: true,
      createdAt: DateTime(2025),
      columns: [
        const SessionColumn(name: 'Barcode', type: SessionColumnType.scan),
        const SessionColumn(name: 'Item Name', type: SessionColumnType.manual),
        const SessionColumn(
          name: 'Qty',
          type: SessionColumnType.manual,
          isNumeric: true,
          defaultValue: '1',
        ),
        const SessionColumn(
          name: 'Bin',
          type: SessionColumnType.fixed,
          fixedValue: '',
          labelPrefix: 'BIN-',
          askAtStart: true,
        ),
        const SessionColumn(
          name: 'Timestamp',
          type: SessionColumnType.timestamp,
        ),
      ],
    ),
    SessionTemplate(
      id: 'builtin_attendance',
      name: 'Attendance',
      icon: 'people_rounded',
      isBuiltIn: true,
      createdAt: DateTime(2025),
      listPrompt:
          'Pick your staff list: badge IDs with names and departments. '
          'Each scan fills them in and shows who isn’t here yet.',
      columns: [
        const SessionColumn(name: 'ID / Badge', type: SessionColumnType.scan),
        const SessionColumn(
          name: 'Name',
          type: SessionColumnType.fromList,
          listField: 'Name',
        ),
        const SessionColumn(
          name: 'Department',
          type: SessionColumnType.fromList,
          listField: 'Department',
        ),
        const SessionColumn(
          name: 'In / Out',
          type: SessionColumnType.pickList,
          choices: ['In', 'Out'],
          defaultValue: 'In',
        ),
        const SessionColumn(
          name: 'Timestamp',
          type: SessionColumnType.timestamp,
        ),
      ],
    ),
    SessionTemplate(
      id: 'builtin_stock_count',
      name: 'Stock count',
      icon: 'inventory_2_rounded',
      isBuiltIn: true,
      createdAt: DateTime(2025),
      listPrompt:
          'Pick your stock list with an expected count for each item. '
          'The sheet then shows what matches, what’s off and what’s not '
          'counted yet.',
      columns: [
        const SessionColumn(name: 'SKU', type: SessionColumnType.scan),
        const SessionColumn(
          name: 'Item',
          type: SessionColumnType.fromList,
          listField: 'Item',
        ),
        const SessionColumn(
          name: 'Qty',
          type: SessionColumnType.manual,
          isNumeric: true,
          defaultValue: '1',
        ),
        const SessionColumn(
          name: 'Bin',
          type: SessionColumnType.fixed,
          fixedValue: '',
          labelPrefix: 'BIN-',
          askAtStart: true,
        ),
        const SessionColumn(
          name: 'Timestamp',
          type: SessionColumnType.timestamp,
        ),
      ],
    ),
    SessionTemplate(
      id: 'builtin_event_checkin',
      name: 'Event Check-in',
      icon: 'confirmation_number_rounded',
      isBuiltIn: true,
      createdAt: DateTime(2025),
      columns: [
        const SessionColumn(name: 'Ticket Code', type: SessionColumnType.scan),
        const SessionColumn(name: 'Attendee', type: SessionColumnType.manual),
        const SessionColumn(
          name: 'Timestamp',
          type: SessionColumnType.timestamp,
        ),
        const SessionColumn(
          name: 'Gate',
          type: SessionColumnType.fixed,
          fixedValue: 'Main',
          askAtStart: true,
        ),
      ],
    ),
    SessionTemplate(
      id: 'builtin_asset_tracking',
      name: 'Asset Tracking',
      icon: 'devices_rounded',
      isBuiltIn: true,
      createdAt: DateTime(2025),
      columns: [
        const SessionColumn(name: 'Asset Code', type: SessionColumnType.scan),
        const SessionColumn(name: 'Asset Tag', type: SessionColumnType.manual),
        const SessionColumn(
          name: 'Condition',
          type: SessionColumnType.pickList,
          choices: ['Good', 'Damaged', 'Missing'],
          defaultValue: 'Good',
        ),
        const SessionColumn(
          name: 'Location',
          type: SessionColumnType.fixed,
          fixedValue: '',
          labelPrefix: 'LOC-',
          askAtStart: true,
        ),
        const SessionColumn(
          name: 'Timestamp',
          type: SessionColumnType.timestamp,
        ),
      ],
    ),
    SessionTemplate(
      id: 'builtin_production_qc',
      name: 'Production / QC',
      icon: 'fact_check',
      isBuiltIn: true,
      createdAt: DateTime(2025),
      columns: [
        const SessionColumn(name: 'Serial No.', type: SessionColumnType.scan),
        const SessionColumn(
          name: 'Result',
          type: SessionColumnType.pickList,
          choices: ['Pass', 'Fail', 'Rework'],
          defaultValue: 'Pass',
        ),
        const SessionColumn(
          name: 'Batch',
          type: SessionColumnType.fixed,
          fixedValue: '',
          askAtStart: true,
        ),
        const SessionColumn(name: 'Note', type: SessionColumnType.manual),
        const SessionColumn(
          name: 'Timestamp',
          type: SessionColumnType.timestamp,
        ),
      ],
    ),
    SessionTemplate(
      id: 'builtin_price_list',
      name: 'Price List',
      icon: 'sell_rounded',
      isBuiltIn: true,
      createdAt: DateTime(2025),
      columns: [
        const SessionColumn(name: 'Barcode', type: SessionColumnType.scan),
        const SessionColumn(
          name: 'Product Name',
          type: SessionColumnType.manual,
        ),
        const SessionColumn(name: 'MRP', type: SessionColumnType.manual),
        const SessionColumn(
          name: 'Timestamp',
          type: SessionColumnType.timestamp,
        ),
      ],
    ),
  ];

  // ─────────────────────────────────────────────────────────────────────────
  // User templates (persisted in Hive)
  // ─────────────────────────────────────────────────────────────────────────

  static List<SessionTemplate> getUserTemplates() {
    final templates = <SessionTemplate>[];
    for (final key in _safeBox.keys) {
      final raw = _safeBox.get(key);
      if (raw == null) continue;
      try {
        templates.add(
          SessionTemplate.fromMap(Map<String, dynamic>.from(raw as Map)),
        );
      } catch (_) {}
    }
    templates.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return templates;
  }

  /// Returns built-in templates first, then user templates sorted by newest.
  static List<SessionTemplate> getAllTemplates() {
    return [...getBuiltInTemplates(), ...getUserTemplates()];
  }

  static SessionTemplate? getTemplate(String id) {
    // Check built-ins first.
    final builtIn = getBuiltInTemplates().where((t) => t.id == id);
    if (builtIn.isNotEmpty) return builtIn.first;
    // Then user templates.
    final raw = _safeBox.get(id);
    if (raw == null) return null;
    try {
      return SessionTemplate.fromMap(Map<String, dynamic>.from(raw as Map));
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveTemplate(SessionTemplate template) async {
    assert(!template.isBuiltIn, 'Cannot save a built-in template.');
    await _safeBox.put(template.id, template.toMap());
  }

  /// Delete a user template. No-op if it is built-in.
  static Future<void> deleteTemplate(String id) async {
    final t = getTemplate(id);
    if (t == null || t.isBuiltIn) return;
    await _safeBox.delete(id);
  }

  /// Clone a template under a new name. Returns the new template.
  static Future<SessionTemplate> duplicateTemplate(
    String id,
    String newName,
  ) async {
    final source = getTemplate(id);
    if (source == null) throw Exception('Template not found: $id');
    final copy = SessionTemplate(
      id: 'user_${DateTime.now().millisecondsSinceEpoch}',
      name: newName,
      icon: source.icon,
      isBuiltIn: false,
      createdAt: DateTime.now(),
      columns: List.from(source.columns),
      listPrompt: source.listPrompt,
    );
    await saveTemplate(copy);
    return copy;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Model
// ─────────────────────────────────────────────────────────────────────────────

class SessionTemplate {
  final String id;
  final String name;
  final String icon; // Material icon name string
  final List<SessionColumn> columns;
  final bool isBuiltIn;
  final DateTime createdAt;

  /// Why this template wants a list, shown when it's picked. Null = it
  /// doesn't use one.
  final String? listPrompt;

  const SessionTemplate({
    required this.id,
    required this.name,
    required this.icon,
    required this.columns,
    required this.isBuiltIn,
    required this.createdAt,
    this.listPrompt,
  });

  /// The columns for a sheet with no list: From list columns become plain
  /// typed columns, so the template still works on a first run.
  List<SessionColumn> get columnsWithoutList => [
    for (final c in columns)
      c.type == SessionColumnType.fromList
          ? SessionColumn(name: c.name, type: SessionColumnType.manual)
          : c,
  ];

  /// Short description shown under the template name in the picker.
  String get columnSummary {
    if (columns.isEmpty) return 'No columns';
    final names = columns.map((c) => c.name).toList();
    if (names.length <= 3) return names.join(', ');
    return '${names.take(3).join(', ')} +${names.length - 3}';
  }

  SessionTemplate copyWith({
    String? name,
    String? icon,
    List<SessionColumn>? columns,
  }) => SessionTemplate(
    id: id,
    name: name ?? this.name,
    icon: icon ?? this.icon,
    columns: columns ?? this.columns,
    isBuiltIn: isBuiltIn,
    createdAt: createdAt,
    listPrompt: listPrompt,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'icon': icon,
    'columns': columns.map((c) => c.toMap()).toList(),
    'isBuiltIn': isBuiltIn,
    'createdAt': createdAt.toIso8601String(),
    'listPrompt': listPrompt,
  };

  factory SessionTemplate.fromMap(Map map) => SessionTemplate(
    id: map['id'] as String,
    name: map['name'] as String,
    icon: map['icon'] as String? ?? 'grid_view_rounded',
    columns: (map['columns'] as List)
        .map((c) => SessionColumn.fromMap(c as Map))
        .toList(),
    isBuiltIn: map['isBuiltIn'] as bool? ?? false,
    createdAt: DateTime.parse(map['createdAt'] as String),
    listPrompt: map['listPrompt'] as String?,
  );
}
