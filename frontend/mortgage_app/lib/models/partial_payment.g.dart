// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'partial_payment.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class PartialPaymentAdapter extends TypeAdapter<PartialPayment> {
  @override
  final int typeId = 5;

  @override
  PartialPayment read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return PartialPayment(
      id: fields[0] as int?,
      entry: fields[1] as int,
      amount: fields[2] as String,
      date: fields[3] as String,
      note: fields[4] == null ? '' : fields[4] as String,
      syncId: fields[5] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, PartialPayment obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.entry)
      ..writeByte(2)
      ..write(obj.amount)
      ..writeByte(3)
      ..write(obj.date)
      ..writeByte(4)
      ..write(obj.note)
      ..writeByte(5)
      ..write(obj.syncId);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PartialPaymentAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
