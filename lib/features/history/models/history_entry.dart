// GENERATED CODE - DO NOT MODIFY BY HAND
// This file is hand-written since we avoid build_runner for simplicity.
// Using a simple Hive model with manual adapter.

import 'package:hive/hive.dart';
import 'dart:typed_data';

@HiveType(typeId: 0)
class HistoryEntry extends HiveObject {
  @HiveField(0)
  late String data;

  @HiveField(1)
  late String dataType; // 'text', 'wifi', 'vcard', 'email'

  @HiveField(2)
  late String generatorType; // 'qr', 'code128', 'ean13', 'upcA'

  @HiveField(3)
  late DateTime createdAt;

  @HiveField(4)
  late String label; // Human-readable label e.g. "https://google.com", "My WiFi"

  @HiveField(5)
  Uint8List? thumbnailBytes; // Cached thumbnail for fast list rendering

  @HiveField(6)
  String? imagePath; // Full high-res image path

  HistoryEntry({
    required this.data,
    required this.dataType,
    required this.generatorType,
    required this.createdAt,
    required this.label,
    this.thumbnailBytes,
    this.imagePath,
  });
}
