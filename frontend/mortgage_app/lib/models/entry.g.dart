// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'entry.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class EntryAdapter extends TypeAdapter<Entry> {
  @override
  final int typeId = 2;

  @override
  Entry read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Entry(
      id: fields[0] as int?,
      srNumber: fields[1] as String,
      party: fields[2] as int,
      amount: fields[3] as String,
      interest: fields[4] as String,
      status: fields[5] as String,
      date: fields[6] as String,
      totalPayable: fields[7] as double,
      daysElapsed: fields[8] == null ? 0 : fields[8] as int,
      partyName: fields[9] == null ? '' : fields[9] as String,
      note: fields[10] == null ? '' : fields[10] as String,
      closedAt: fields[11] as String?,
      syncId: fields[12] as String?,
      dueDate: fields[13] as String?,
      version: fields[14] == null ? 1 : fields[14] as int,
      totalPaid: fields[15] as double?,
      remainingPrincipal: fields[16] as double?,
      totalAccruedInterest: fields[17] as double?,
    );
  }

  @override
  void write(BinaryWriter writer, Entry obj) {
    writer
      ..writeByte(18)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.srNumber)
      ..writeByte(2)
      ..write(obj.party)
      ..writeByte(3)
      ..write(obj.amount)
      ..writeByte(4)
      ..write(obj.interest)
      ..writeByte(5)
      ..write(obj.status)
      ..writeByte(6)
      ..write(obj.date)
      ..writeByte(7)
      ..write(obj.totalPayable)
      ..writeByte(8)
      ..write(obj.daysElapsed)
      ..writeByte(9)
      ..write(obj.partyName)
      ..writeByte(10)
      ..write(obj.note)
      ..writeByte(11)
      ..write(obj.closedAt)
      ..writeByte(12)
      ..write(obj.syncId)
      ..writeByte(13)
      ..write(obj.dueDate)
      ..writeByte(14)
      ..write(obj.version)
      ..writeByte(15)
      ..write(obj.totalPaid)
      ..writeByte(16)
      ..write(obj.remainingPrincipal)
      ..writeByte(17)
      ..write(obj.totalAccruedInterest);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EntryAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
