import 'package:hive/hive.dart';

part 'jewellery_item.g.dart';

@HiveType(typeId: 3)
class JewelleryItem extends HiveObject {
  @HiveField(0)
  int? id;

  @HiveField(1)
  int entry;

  @HiveField(2)
  String itemType;

  @HiveField(3)
  String name;

  @HiveField(4)
  double? weight;

  @HiveField(5, defaultValue: '')
  String note;

  @HiveField(6)
  String? image;

  @HiveField(7)
  String? syncId;

  @HiveField(8, defaultValue: 1)
  int version;

  @HiveField(9, defaultValue: 'held')
  String releaseStatus;

  @HiveField(10)
  String? releaseDate;

  @HiveField(11)
  String? releaseNote;

  JewelleryItem({
    this.id,
    required this.entry,
    required this.itemType,
    required this.name,
    this.weight,
    this.note = '',
    this.image,
    this.syncId,
    this.version = 1,
    this.releaseStatus = 'held',
    this.releaseDate,
    this.releaseNote,
  });

  factory JewelleryItem.fromJson(Map<String, dynamic> json) {
    return JewelleryItem(
      id: json['id'],
      entry: json['entry'],
      itemType: json['item_type'],
      name: json['name'],
      weight: json['weight']?.toDouble(),
      note: json['note'] ?? '',
      image: json['image'],
      syncId: json['sync_id'],
      version: json['version'] ?? 1,
      releaseStatus: json['release_status'] ?? 'held',
      releaseDate: json['release_date'],
      releaseNote: json['release_note'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'entry': entry,
      'item_type': itemType,
      'name': name,
      if (weight != null) 'weight': weight,
      'note': note,
      if (syncId != null) 'sync_id': syncId,
      'version': version,
      'release_status': releaseStatus,
      if (releaseDate != null) 'release_date': releaseDate,
      if (releaseNote != null) 'release_note': releaseNote,
    };
  }
}
