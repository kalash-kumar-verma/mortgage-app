import 'package:hive/hive.dart';

part 'sync_action.g.dart';

/// Lifecycle states for a queued sync operation.
/// pending   → action is waiting to be sent
/// syncing   → currently in flight
/// failed    → last attempt failed; will retry if retryCount < maxRetries
/// conflict  → server returned 409 (version mismatch); needs user resolution
class SyncStatus {
  static const pending  = 'pending';
  static const syncing  = 'syncing';
  static const failed   = 'failed';
  static const conflict = 'conflict';
}

@HiveType(typeId: 4)
class SyncAction extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String method; // POST, PATCH, DELETE

  @HiveField(2)
  final String endpoint; // e.g. "parties/" or "entries/15/"

  @HiveField(3)
  String? payload; // JSON encoded string

  @HiveField(4)
  final DateTime timestamp;

  @HiveField(5)
  bool isSyncing; // legacy field — kept to avoid breaking existing stored records

  /// Lifecycle status: 'pending' | 'syncing' | 'failed'
  @HiveField(6)
  String status;

  /// Number of failed attempts. After maxRetries the action is abandoned.
  @HiveField(7)
  int retryCount;

  /// Last error message from a failed attempt. Displayed in settings/debug.
  @HiveField(8)
  String? failureReason;

  /// Unique key sent to server to prevent duplicate processing.
  /// The server uses this to detect and de-duplicate retried requests.
  @HiveField(9)
  String idempotencyKey;

  static const int maxRetries = 5;

  SyncAction({
    required this.id,
    required this.method,
    required this.endpoint,
    this.payload,
    required this.timestamp,
    this.isSyncing       = false,
    this.status          = SyncStatus.pending,
    this.retryCount      = 0,
    this.failureReason,
    String? idempotencyKey,
  }) : idempotencyKey = idempotencyKey ?? id; // default: same as action ID

  bool get canRetry => retryCount < maxRetries;

  bool get isAbandoned => retryCount >= maxRetries;
}
