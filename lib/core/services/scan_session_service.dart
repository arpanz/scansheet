import 'package:hive_flutter/hive_flutter.dart';
import '../../features/scan/models/scan_session.dart';

/// Dedicated service for Scan Session CRUD.
/// Uses two Hive boxes:
///   - 'scan_session_meta'  → session metadata (name, columns, flags)
///   - 'scan_session_rows'  → individual rows keyed by '{sessionId}_{rowIndex}'
///
/// Rows are stored individually (append-only) so we never deserialize
/// an entire session on each scan — only the metadata is loaded for list views.
class ScanSessionService {
  static const _metaBoxName = 'scan_session_meta';
  static const _rowsBoxName = 'scan_session_rows';

  static Box? _metaBox;
  static Box? _rowsBox;

  static Future<void> init() async {
    _metaBox = await Hive.openBox(_metaBoxName);
    _rowsBox = await Hive.openBox(_rowsBoxName);
  }

  static Box get metaBox {
    assert(_metaBox != null, 'Call ScanSessionService.init() before use.');
    return _metaBox!;
  }

  static Box get rowsBox {
    assert(_rowsBox != null, 'Call ScanSessionService.init() before use.');
    return _rowsBox!;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Session CRUD
  // ─────────────────────────────────────────────────────────────────────────

  /// Save (upsert) a session's metadata. Does NOT touch rows.
  static Future<void> saveSession(ScanSession session) async {
    await metaBox.put(session.id, session.toMap());
  }

  static ScanSession? getSession(String id) {
    final raw = metaBox.get(id);
    if (raw == null) return null;
    return ScanSession.fromMap(Map<String, dynamic>.from(raw as Map));
  }

  /// Returns the currently active session (isActive == true), or null.
  static ScanSession? getActiveSession() {
    for (final key in metaBox.keys) {
      final raw = metaBox.get(key);
      if (raw == null) continue;
      final map = Map<String, dynamic>.from(raw as Map);
      if (map['isActive'] == true) {
        return ScanSession.fromMap(map);
      }
    }
    return null;
  }

  /// All sessions sorted by createdAt descending (newest first).
  static List<ScanSession> getAllSessions() {
    final sessions = <ScanSession>[];
    for (final key in metaBox.keys) {
      final raw = metaBox.get(key);
      if (raw == null) continue;
      try {
        sessions.add(
          ScanSession.fromMap(Map<String, dynamic>.from(raw as Map)),
        );
      } catch (_) {}
    }
    sessions.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return sessions;
  }

  /// Mark a session as completed (no longer active).
  static Future<void> endSession(String id) async {
    final session = getSession(id);
    if (session == null) return;
    await saveSession(
      session.copyWith(isActive: false, completedAt: DateTime.now()),
    );
  }

  /// Delete a session and ALL its rows.
  static Future<void> deleteSession(String id) async {
    await metaBox.delete(id);
    // Delete all rows for this session.
    final rowKeys = rowsBox.keys
        .where((k) => k.toString().startsWith('${id}_'))
        .toList();
    for (final key in rowKeys) {
      await rowsBox.delete(key);
    }
  }

  /// Clear all sessions and all rows.
  static Future<void> clearAll() async {
    await metaBox.clear();
    await rowsBox.clear();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Row operations (append-only pattern)
  // ─────────────────────────────────────────────────────────────────────────

  static String _rowKey(String sessionId, int rowIndex) =>
      '${sessionId}_$rowIndex';

  /// Append a new row to the session.
  static Future<void> addRow(String sessionId, SessionRow row) async {
    await rowsBox.put(_rowKey(sessionId, row.rowIndex), row.toMap());
  }

  /// Replace an existing row. Used when correcting scanned values.
  static Future<void> updateRow(String sessionId, SessionRow row) async {
    await rowsBox.put(_rowKey(sessionId, row.rowIndex), row.toMap());
  }

  /// Load all rows for a session, sorted by rowIndex ascending.
  static List<SessionRow> getRows(String sessionId) {
    final prefix = '${sessionId}_';
    final rows = <SessionRow>[];
    for (final key in rowsBox.keys) {
      if (!key.toString().startsWith(prefix)) continue;
      final raw = rowsBox.get(key);
      if (raw == null) continue;
      try {
        rows.add(SessionRow.fromMap(Map<String, dynamic>.from(raw as Map)));
      } catch (_) {}
    }
    rows.sort((a, b) => a.rowIndex.compareTo(b.rowIndex));
    return rows;
  }

  /// Delete the last committed row. Used for single-level undo.
  static Future<void> deleteLastRow(String sessionId) async {
    final rows = getRows(sessionId);
    if (rows.isEmpty) return;
    final last = rows.last;
    await rowsBox.delete(_rowKey(sessionId, last.rowIndex));
  }

  /// Delete all rows for a session (used by "Clear All Rows" in session screen).
  static Future<void> clearRows(String sessionId) async {
    final rowKeys = rowsBox.keys
        .where((k) => k.toString().startsWith('${sessionId}_'))
        .toList();
    for (final key in rowKeys) {
      await rowsBox.delete(key);
    }
  }

  /// Row count for a session (fast — just counts matching keys).
  static int getRowCount(String sessionId) {
    final prefix = '${sessionId}_';
    return rowsBox.keys.where((k) => k.toString().startsWith(prefix)).length;
  }

  /// Check if a value already exists in a specific column across all rows.
  static bool isDuplicate(String sessionId, int columnIndex, String value) {
    if (value.isEmpty) return false;
    final rows = getRows(sessionId);
    return rows.any(
      (r) => r.values.length > columnIndex && r.values[columnIndex] == value,
    );
  }
}
