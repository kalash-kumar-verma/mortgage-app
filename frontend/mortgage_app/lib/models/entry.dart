import 'package:hive/hive.dart';

part 'entry.g.dart';

@HiveType(typeId: 2)
class Entry extends HiveObject {
  @HiveField(0)
  int? id;

  @HiveField(1)
  String srNumber;

  @HiveField(2)
  int party;

  @HiveField(3)
  String amount;

  @HiveField(4)
  String interest;

  @HiveField(5)
  String status;

  @HiveField(6)
  String date;

  @HiveField(7)
  double totalPayable;

  @HiveField(8)
  int daysElapsed;

  @HiveField(9)
  String partyName;

  @HiveField(10)
  String note;

  @HiveField(11)
  String? closedAt;

  @HiveField(12)
  String? syncId;

  Entry({
    this.id,
    required this.srNumber,
    required this.party,
    required this.amount,
    required this.interest,
    required this.status,
    required this.date,
    required this.totalPayable,
    required this.daysElapsed,
    required this.partyName,
    this.note = '',
    this.closedAt,
    this.syncId,
  });

  factory Entry.fromJson(Map<String, dynamic> json) {
    return Entry(
      id: json['id'],
      srNumber: json['sr_number'] ?? '',
      party: json['party'],
      amount: json['amount'],
      interest: json['interest'],
      status: json['status'],
      date: json['date'],
      totalPayable: json['total_payable']?.toDouble() ?? 0.0,
      daysElapsed: json['days_elapsed'] ?? 0,
      partyName: json['party_name'] ?? '',
      note: json['note'] ?? '',
      closedAt: json['closed_at'],
      syncId: json['sync_id'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'sr_number': srNumber,
      'party': party,
      'amount': amount,
      'interest': interest,
      'status': status,
      'note': note,
      if (syncId != null) 'sync_id': syncId,
    };
  }
}
