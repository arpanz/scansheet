// Manual Hive TypeAdapter since we skip build_runner for simplicity.
import 'package:hive/hive.dart';
import 'dart:typed_data';
import 'history_entry.dart';

class HistoryEntryAdapter extends TypeAdapter<HistoryEntry> {
  @override
  final int typeId = 0;

  @override
  HistoryEntry read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return HistoryEntry(
      data: fields[0] as String,
      dataType: fields[1] as String,
      generatorType: fields[2] as String,
      createdAt: fields[3] as DateTime,
      label: fields[4] as String,
      thumbnailBytes: fields[5] as Uint8List?,
      imagePath: fields[6] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, HistoryEntry obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.data)
      ..writeByte(1)
      ..write(obj.dataType)
      ..writeByte(2)
      ..write(obj.generatorType)
      ..writeByte(3)
      ..write(obj.createdAt)
      ..writeByte(4)
      ..write(obj.label)
      ..writeByte(5)
      ..write(obj.thumbnailBytes)
      ..writeByte(6)
      ..write(obj.imagePath);
  }
}
