import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../features/scan/models/scan_session.dart';
import '../models/sync_queue_item.dart';
import 'scan_session_service.dart';
import 'sync_queue_service.dart';

/// Read-model for list screens: one sheet plus the numbers its row shows.
class SheetSummary {
  final ScanSession session;
  final int rowCount;
  final int rowsToday;
  final DateTime lastActivity;
  final int pending;
  final int failed;

  const SheetSummary._({
    required this.session,
    required this.rowCount,
    required this.rowsToday,
    required this.lastActivity,
    required this.pending,
    required this.failed,
  });

  bool get isSheets => session.destination == SessionDestination.googleSheets;

  String get destinationLabel => switch (session.destination) {
    SessionDestination.googleSheets => 'Google Sheets',
    SessionDestination.localXlsx => 'Excel',
    SessionDestination.localCsv => 'CSV',
  };

  String get columnsLine => session.columns.map((c) => c.name).join(' · ');

  /// All sheets, most recently used first.
  static List<SheetSummary> all() {
    final queue = SyncQueueService.getAll();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final list = ScanSessionService.getAllSessions().map((s) {
      final rows = ScanSessionService.getRows(s.id);
      var last = s.createdAt;
      var todayCount = 0;
      for (final r in rows) {
        if (r.scannedAt.isAfter(last)) last = r.scannedAt;
        if (!r.scannedAt.isBefore(today)) todayCount++;
      }
      final mine = queue.where((i) => i.sessionId == s.id);
      return SheetSummary._(
        session: s,
        rowCount: rows.length,
        rowsToday: todayCount,
        lastActivity: last,
        pending: mine
            .where(
              (i) =>
                  i.status == SyncStatus.pending ||
                  i.status == SyncStatus.syncing,
            )
            .length,
        failed: mine.where((i) => i.status == SyncStatus.failed).length,
      );
    }).toList();
    list.sort((a, b) => b.lastActivity.compareTo(a.lastActivity));
    return list;
  }

  /// The sheet the Scan button resumes: the most recently used open sheet.
  static SheetSummary? inProgress(List<SheetSummary> all) {
    for (final s in all) {
      if (s.session.isActive) return s;
    }
    return null;
  }
}

/// "now", "2 min ago", "Yesterday", "Monday", "12 Oct".
String relativeTime(DateTime t) {
  final now = DateTime.now();
  final diff = now.difference(t);
  if (diff.inMinutes < 1) return 'now';
  if (diff.inHours < 1) return '${diff.inMinutes} min ago';
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(t.year, t.month, t.day);
  final days = today.difference(day).inDays;
  if (days == 0) return '${diff.inHours} h ago';
  if (days == 1) return 'Yesterday';
  const weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  if (days < 7) return weekdays[t.weekday - 1];
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${t.day} ${months[t.month - 1]}';
}

/// Lucide icon for a sheet's stored icon key (keys from the sheet setup flow
/// and template icon names).
IconData sheetIcon(String? key) {
  final k = key ?? '';
  if (k.startsWith('inventory') || k == 'warehouse') return LucideIcons.package;
  if (k.startsWith('people')) return LucideIcons.users;
  if (k.startsWith('confirmation') || k == 'receipt') return LucideIcons.ticket;
  if (k.startsWith('devices')) return LucideIcons.laptop;
  if (k.startsWith('sell')) return LucideIcons.tag;
  if (k == 'store') return LucideIcons.store;
  if (k == 'local_shipping') return LucideIcons.truck;
  if (k == 'fact_check') return LucideIcons.clipboardCheck;
  if (k == 'science') return LucideIcons.flaskConical;
  if (k == 'local_hospital') return LucideIcons.hospital;
  if (k == 'construction') return LucideIcons.hammer;
  return LucideIcons.sheet;
}
