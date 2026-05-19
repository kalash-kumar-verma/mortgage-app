import 'package:hive/hive.dart';

part 'activity_log.g.dart';

@HiveType(typeId: 6)
class ActivityLog extends HiveObject {
  @HiveField(0)
  String syncId;

  @HiveField(1)
  String action; // CREATE, EDIT, DELETE, WITHDRAW, PAYMENT, PROFILE

  @HiveField(2)
  String entityType; // PARTY, ENTRY, ITEM, PAYMENT, PROFILE

  @HiveField(3)
  int? entityId; // nullable for offline creation

  @HiveField(4)
  String? entitySyncId;

  @HiveField(5)
  String entityNameSnapshot; // e.g., 'SR-1025' or 'John Doe'

  @HiveField(6)
  DateTime timestamp;

  @HiveField(7)
  String description;

  @HiveField(8)
  String? oldValues; // JSON string

  @HiveField(9)
  String? newValues; // JSON string

  ActivityLog({
    required this.syncId,
    required this.action,
    required this.entityType,
    this.entityId,
    this.entitySyncId,
    this.entityNameSnapshot = '',
    required this.timestamp,
    required this.description,
    this.oldValues,
    this.newValues,
  });

  factory ActivityLog.fromJson(Map<String, dynamic> json) {
    return ActivityLog(
      syncId: json['sync_id'],
      action: json['action'],
      entityType: json['entity_type'],
      entityId: json['entity_id'],
      entitySyncId: json['entity_sync_id'],
      entityNameSnapshot: json['entity_name_snapshot'] ?? '',
      timestamp: DateTime.parse(json['timestamp']).toLocal(),
      description: json['description'] ?? '',
      oldValues: json['old_values'] != null ? json['old_values'].toString() : null,
      newValues: json['new_values'] != null ? json['new_values'].toString() : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'sync_id': syncId,
      'action': action,
      'entity_type': entityType,
      if (entityId != null) 'entity_id': entityId,
      if (entitySyncId != null) 'entity_sync_id': entitySyncId,
      'entity_name_snapshot': entityNameSnapshot,
      'timestamp': timestamp.toUtc().toIso8601String(),
      'description': description,
      if (oldValues != null) 'old_values': oldValues,
      if (newValues != null) 'new_values': newValues,
    };
  }
}
