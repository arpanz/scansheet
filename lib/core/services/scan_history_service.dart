import 'package:hive_flutter/hive_flutter.dart';

class ScanEntry {
  final String raw;
  final String type; // 'url', 'wifi', 'vcard', 'email', 'phone', 'sms', 'geo', 'text'
  final DateTime scannedAt;

  ScanEntry({required this.raw, required this.type, required this.scannedAt});

  Map<String, dynamic> toMap() => {
    'raw': raw,
    'type': type,
    'scannedAt': scannedAt.toIso8601String(),
  };

  factory ScanEntry.fromMap(Map map) => ScanEntry(
    raw: map['raw'] as String,
    type: map['type'] as String,
    scannedAt: DateTime.parse(map['scannedAt'] as String),
  );

  static String detectType(String raw) {
    final v = raw.trim();
    if (v.startsWith('http://') || v.startsWith('https://')) return 'url';
    if (v.startsWith('WIFI:')) return 'wifi';
    if (v.startsWith('BEGIN:VCARD') || v.startsWith('MECARD:')) return 'vcard';
    if (v.startsWith('mailto:') ||
        RegExp(r'^[\w.+-]+@[\w-]+\.[\w.]+$').hasMatch(v)) {
      return 'email';
    }
    if (v.startsWith('tel:') ||
        RegExp(r'^\+?[0-9\s\-().]{7,}$').hasMatch(v)) {
      return 'phone';
    }
    if (v.startsWith('smsto:') || v.startsWith('sms:')) return 'sms';
    if (v.startsWith('geo:')) return 'geo';
    return 'text';
  }
}

class ScanHistoryService {
  static const _boxName = 'scan_history';
  static Box? _box;

  static Future<void> init() async {
    _box = await Hive.openBox(_boxName);
  }

  static Box get box {
    assert(_box != null, 'Call ScanHistoryService.init() before use.');
    return _box!;
  }

  static Future<void> save(ScanEntry entry) async {
    await box.add(entry.toMap());
  }

  static List<ScanEntry> getAll() {
    final list = box.values
        .map((v) => ScanEntry.fromMap(Map<String, dynamic>.from(v as Map)))
        .toList();
    list.sort((a, b) => b.scannedAt.compareTo(a.scannedAt));
    return list;
  }

  /// Delete a specific entry by matching raw data + timestamp.
  /// This is the safe deletion method — Hive box keys are auto-incremented
  /// integers and do NOT correspond to list indices after any prior deletions.
  static Future<void> deleteEntry(ScanEntry entry) async {
    final target = entry.scannedAt.toIso8601String();
    for (final key in box.keys) {
      final v = box.get(key);
      if (v is Map && v['scannedAt'] == target && v['raw'] == entry.raw) {
        await box.delete(key);
        return;
      }
    }
  }

  static Future<void> clear() async {
    await box.clear();
  }
}
