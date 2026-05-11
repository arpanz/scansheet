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
            const SessionColumn(name: 'Qty', type: SessionColumnType.increment),
            const SessionColumn(
              name: 'Location',
              type: SessionColumnType.fixed,
              fixedValue: '',
            ),
            const SessionColumn(name: 'Timestamp', type: SessionColumnType.timestamp),
          ],
        ),
        SessionTemplate(
          id: 'builtin_attendance',
          name: 'Attendance',
          icon: 'people_rounded',
          isBuiltIn: true,
          createdAt: DateTime(2025),
          columns: [
            const SessionColumn(name: 'ID / Badge', type: SessionColumnType.scan),
            const SessionColumn(name: 'Name', type: SessionColumnType.manual),
            const SessionColumn(name: 'Timestamp', type: SessionColumnType.timestamp),
            const SessionColumn(
              name: 'Status',
              type: SessionColumnType.fixed,
              fixedValue: 'Present',
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
            const SessionColumn(name: 'Timestamp', type: SessionColumnType.timestamp),
            const SessionColumn(
              name: 'Gate',
              type: SessionColumnType.fixed,
              fixedValue: 'Main',
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
              name: 'Location',
              type: SessionColumnType.fixed,
              fixedValue: '',
            ),
            const SessionColumn(name: 'Timestamp', type: SessionColumnType.timestamp),
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
            const SessionColumn(name: 'Product Name', type: SessionColumnType.manual),
            const SessionColumn(name: 'MRP', type: SessionColumnType.manual),
            const SessionColumn(name: 'Timestamp', type: SessionColumnType.timestamp),
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

  const SessionTemplate({
    required this.id,
    required this.name,
    required this.icon,
    required this.columns,
    required this.isBuiltIn,
    required this.createdAt,
  });

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
  }) =>
      SessionTemplate(
        id: id,
        name: name ?? this.name,
        icon: icon ?? this.icon,
        columns: columns ?? this.columns,
        isBuiltIn: isBuiltIn,
        createdAt: createdAt,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'icon': icon,
        'columns': columns.map((c) => c.toMap()).toList(),
        'isBuiltIn': isBuiltIn,
        'createdAt': createdAt.toIso8601String(),
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
      );
}
