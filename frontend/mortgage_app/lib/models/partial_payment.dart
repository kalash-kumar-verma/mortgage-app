import 'package:hive/hive.dart';

part 'partial_payment.g.dart';

@HiveType(typeId: 5)
class PartialPayment extends HiveObject {
  @HiveField(0)
  int? id;

  @HiveField(1)
  int entry;

  @HiveField(2)
  String amount;

  @HiveField(3)
  String date;

  @HiveField(4, defaultValue: '')
  String note;

  @HiveField(5)
  String? syncId;

  PartialPayment({
    this.id,
    required this.entry,
    required this.amount,
    required this.date,
    this.note = '',
    this.syncId,
  });

  factory PartialPayment.fromJson(Map<String, dynamic> json) {
    return PartialPayment(
      id:      json['id'],
      entry:   json['entry'],
      amount:  json['amount'],
      date:    json['date'],
      note:    json['note'] ?? '',
      syncId:  json['sync_id'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'entry':  entry,
      'amount': amount,
      'date':   date,
      'note':   note,
      if (syncId != null) 'sync_id': syncId,
    };
  }
}
