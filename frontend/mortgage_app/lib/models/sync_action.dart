import 'package:hive/hive.dart';

part 'sync_action.g.dart';

@HiveType(typeId: 4)
class SyncAction extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String method; // POST, PATCH, DELETE

  @HiveField(2)
  final String endpoint; // e.g. "parties/" or "entries/15/"

  @HiveField(3)
  final String? payload; // JSON encoded string

  @HiveField(4)
  final DateTime timestamp;

  @HiveField(5)
  bool isSyncing;

  SyncAction({
    required this.id,
    required this.method,
    required this.endpoint,
    this.payload,
    required this.timestamp,
    this.isSyncing = false,
  });
}
