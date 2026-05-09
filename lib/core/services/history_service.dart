import 'package:hive_flutter/hive_flutter.dart';
import 'package:batchqr/features/history/models/history_entry.dart';
import 'package:batchqr/features/history/models/history_entry.g.dart';

class HistoryService {
  static const _boxName = 'history';
  static Box<HistoryEntry>? _box;

  static Future<void> init() async {
    Hive.registerAdapter(HistoryEntryAdapter());
    _box = await Hive.openBox<HistoryEntry>(_boxName);
  }

  static Box<HistoryEntry> get box {
    assert(_box != null, 'Call HistoryService.init() before use.');
    return _box!;
  }

  static Future<void> save(HistoryEntry entry) async {
    await box.add(entry);
  }

  static List<HistoryEntry> getAll() {
    final list = box.values.toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  static Future<void> delete(HistoryEntry entry) async {
    await entry.delete();
  }

  static Future<void> clear() async {
    await box.clear();
  }
}
