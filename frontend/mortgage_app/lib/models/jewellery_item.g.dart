// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'jewellery_item.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class JewelleryItemAdapter extends TypeAdapter<JewelleryItem> {
  @override
  final int typeId = 3;

  @override
  JewelleryItem read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return JewelleryItem(
      id: fields[0] as int?,
      entry: fields[1] as int,
      itemType: fields[2] as String,
      name: fields[3] as String,
      weight: fields[4] as double?,
      note: fields[5] == null ? '' : fields[5] as String,
      image: fields[6] as String?,
      syncId: fields[7] as String?,
      version: fields[8] == null ? 1 : fields[8] as int,
      releaseStatus: fields[9] == null ? 'held' : fields[9] as String,
      releaseDate: fields[10] as String?,
      releaseNote: fields[11] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, JewelleryItem obj) {
    writer
      ..writeByte(12)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.entry)
      ..writeByte(2)
      ..write(obj.itemType)
      ..writeByte(3)
      ..write(obj.name)
      ..writeByte(4)
      ..write(obj.weight)
      ..writeByte(5)
      ..write(obj.note)
      ..writeByte(6)
      ..write(obj.image)
      ..writeByte(7)
      ..write(obj.syncId)
      ..writeByte(8)
      ..write(obj.version)
      ..writeByte(9)
      ..write(obj.releaseStatus)
      ..writeByte(10)
      ..write(obj.releaseDate)
      ..writeByte(11)
      ..write(obj.releaseNote);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is JewelleryItemAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
