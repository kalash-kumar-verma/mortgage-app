// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sync_action.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class SyncActionAdapter extends TypeAdapter<SyncAction> {
  @override
  final int typeId = 4;

  @override
  SyncAction read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return SyncAction(
      id:               fields[0] as String,
      method:           fields[1] as String,
      endpoint:         fields[2] as String,
      payload:          fields[3] as String?,
      timestamp:        fields[4] as DateTime,
      isSyncing:        fields[5] as bool? ?? false,
      status:           fields[6] as String? ?? 'pending',   // safe default for old records
      retryCount:       fields[7] as int?    ?? 0,
      failureReason:    fields[8] as String?,
      idempotencyKey:   fields[9] as String?,                // will fallback to id in constructor
    );
  }

  @override
  void write(BinaryWriter writer, SyncAction obj) {
    writer
      ..writeByte(10)   // total number of fields
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.method)
      ..writeByte(2)
      ..write(obj.endpoint)
      ..writeByte(3)
      ..write(obj.payload)
      ..writeByte(4)
      ..write(obj.timestamp)
      ..writeByte(5)
      ..write(obj.isSyncing)
      ..writeByte(6)
      ..write(obj.status)
      ..writeByte(7)
      ..write(obj.retryCount)
      ..writeByte(8)
      ..write(obj.failureReason)
      ..writeByte(9)
      ..write(obj.idempotencyKey);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SyncActionAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
