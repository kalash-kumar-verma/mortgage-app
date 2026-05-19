// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'activity_log.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ActivityLogAdapter extends TypeAdapter<ActivityLog> {
  @override
  final int typeId = 6;

  @override
  ActivityLog read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ActivityLog(
      syncId: fields[0] as String,
      action: fields[1] as String,
      entityType: fields[2] as String,
      entityId: fields[3] as int?,
      entitySyncId: fields[4] as String?,
      entityNameSnapshot: fields[5] as String,
      timestamp: fields[6] as DateTime,
      description: fields[7] as String,
      oldValues: fields[8] as String?,
      newValues: fields[9] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, ActivityLog obj) {
    writer
      ..writeByte(10)
      ..writeByte(0)
      ..write(obj.syncId)
      ..writeByte(1)
      ..write(obj.action)
      ..writeByte(2)
      ..write(obj.entityType)
      ..writeByte(3)
      ..write(obj.entityId)
      ..writeByte(4)
      ..write(obj.entitySyncId)
      ..writeByte(5)
      ..write(obj.entityNameSnapshot)
      ..writeByte(6)
      ..write(obj.timestamp)
      ..writeByte(7)
      ..write(obj.description)
      ..writeByte(8)
      ..write(obj.oldValues)
      ..writeByte(9)
      ..write(obj.newValues);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ActivityLogAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
