import 'package:hive/hive.dart';

part 'party.g.dart';

@HiveType(typeId: 1)
class Party extends HiveObject {
  @HiveField(0)
  int? id;

  @HiveField(1)
  String name;

  @HiveField(2)
  String phone;

  @HiveField(3)
  String address;

  @HiveField(4, defaultValue: '')
  String note;

  @HiveField(5, defaultValue: '')
  String createdAt;

  @HiveField(6)
  double? defaultInterestRate;

  @HiveField(7)
  String? syncId;

  @HiveField(8)
  String? accountNumber;

  Party({
    this.id,
    required this.name,
    required this.phone,
    required this.address,
    this.note = '',
    this.createdAt = '',
    this.defaultInterestRate,
    this.syncId,
    this.accountNumber,
  });

  factory Party.fromJson(Map<String, dynamic> json) {
    return Party(
      id: json['id'],
      name: json['name'],
      phone: json['phone'] ?? '',
      address: json['address'] ?? '',
      note: json['note'] ?? '',
      createdAt: json['created_at'] ?? '',
      defaultInterestRate: json['default_interest_rate'] != null 
          ? double.tryParse(json['default_interest_rate'].toString()) 
          : null,
      syncId: json['sync_id'],
      accountNumber: json['account_number'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'phone': phone,
      'address': address,
      'note': note,
      if (defaultInterestRate != null) 'default_interest_rate': defaultInterestRate,
      if (syncId != null) 'sync_id': syncId,
      if (accountNumber != null) 'account_number': accountNumber,
    };
  }
}
