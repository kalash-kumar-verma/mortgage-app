import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'package:hive/hive.dart';
import '../models/sync_action.dart';
import 'api_service.dart';
import 'local_db_service.dart';
import 'settings_service.dart';

/// SyncManager — Offline-first background sync engine.
///
/// Responsibilities:
///   1. Push pending local operations to server (chronological order)
///   2. Pull new server records into local Hive store
///   3. Recover from crash (reset stuck "syncing" actions on startup)
///   4. Retry failed actions on a periodic timer (60s)
///   5. Prevent duplicate operation processing via idempotency keys
///   6. Expose reactive notifiers for UI (isSyncing, isOnline, pendingCount)
///
/// Architecture:
///   - Singleton pattern (one instance per app lifecycle)
///   - All mutations go through LocalDbService first (local-first guarantee)
///   - SyncManager only reads the queue and pushes — never writes app data directly
class SyncManager {
  static final SyncManager _instance = SyncManager._internal();
  factory SyncManager() => _instance;
  SyncManager._internal();

  // ─── Public Notifiers (subscribe in any widget) ───────────────────────────

  /// True while a sync cycle is running.
  final ValueNotifier<bool> isSyncingNotifier = ValueNotifier(false);

  /// True when the device has an active internet connection.
  final ValueNotifier<bool> isOnlineNotifier = ValueNotifier(false);

  /// Number of pending sync operations in the queue.
  /// Includes pending + failed-but-retryable actions.
  final ValueNotifier<int> pendingCountNotifier = ValueNotifier(0);

  // ─── Private State ────────────────────────────────────────────────────────

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _retryTimer;
  bool _isSyncing = false;
  bool _initialized = false;
  final Set<String> _recentlyResolvedSyncIds = {};

  // ─── Lifecycle ────────────────────────────────────────────────────────────

  /// Call once after user boxes are opened (after login or on app resume).
  void initialize() {
    if (_initialized) return;
    _initialized = true;

    debugPrint('[SyncManager] Initializing...');

    // ① Crash recovery: reset any action that was stuck mid-flight
    _resetStuckSyncingActions();

    // ② Update pending count for UI
    _updatePendingCount();

    // ③ Check initial connectivity
    _checkInitialConnectivity();

    // ④ Listen for connectivity changes
    _connectivitySubscription = Connectivity()
        .onConnectivityChanged
        .listen(_onConnectivityChanged);

    // ⑤ Periodic retry timer — 60s interval
    //    Catches failures that didn't trigger a connectivity event
    //    (e.g., server was down but network was up)
    _retryTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      debugPrint('[SyncManager] Periodic retry tick...');
      _syncAll();
    });

    // ⑥ Attempt an immediate sync on startup
    _syncAll();
  }

  void dispose() {
    _connectivitySubscription?.cancel();
    _retryTimer?.cancel();
    _connectivitySubscription = null;
    _retryTimer = null;
    _initialized = false;
    _isSyncing = false;
    isSyncingNotifier.value = false;
    pendingCountNotifier.value = 0;
    debugPrint('[SyncManager] Disposed.');
  }

  // ─── Crash Recovery ───────────────────────────────────────────────────────

  /// Reset actions that were marked "syncing" but the app crashed before
  /// they could be confirmed as synced or failed.
  /// These actions will be re-attempted on the next sync cycle.
  void _resetStuckSyncingActions() {
    try {
      final box = LocalDbService.syncBox;
      int resetCount = 0;
      for (final key in box.keys) {
        final action = box.get(key);
        if (action == null) continue;
        if (action.status == SyncStatus.syncing || action.isSyncing) {
          action.status    = SyncStatus.pending;
          action.isSyncing = false;
          action.save();  // fire-and-forget (sync-safe for Hive)
          resetCount++;
        }
      }
      if (resetCount > 0) {
        debugPrint('[SyncManager] Reset $resetCount stuck syncing action(s) → pending.');
      }
    } catch (e) {
      debugPrint('[SyncManager] _resetStuckSyncingActions error: $e');
    }
  }

  // ─── Connectivity Handling ────────────────────────────────────────────────

  Future<void> _checkInitialConnectivity() async {
    try {
      final results = await Connectivity().checkConnectivity();
      final online = !results.contains(ConnectivityResult.none);
      isOnlineNotifier.value = online;
    } catch (_) {
      isOnlineNotifier.value = false;
    }
  }

  void _onConnectivityChanged(List<ConnectivityResult> result) {
    final nowOnline = !result.contains(ConnectivityResult.none);
    final wasOnline = isOnlineNotifier.value;
    isOnlineNotifier.value = nowOnline;

    if (nowOnline && !wasOnline) {
      // Just came back online — sync immediately
      debugPrint('[SyncManager] Network restored — triggering sync.');
      _syncAll();
    } else if (!nowOnline) {
      debugPrint('[SyncManager] Network lost — sync will resume when online.');
    }
  }

  // ─── Sync Orchestration ───────────────────────────────────────────────────

  /// Full sync cycle: push pending local changes → pull new server data.
  /// Guards against concurrent cycles with _isSyncing flag.
  Future<void> _syncAll({bool isManual = false}) async {
    if (_isSyncing) return;

    if (!isManual) {
      final lastSync = SettingsService.lastSyncedAt;
      final queueEmpty = LocalDbService.getPendingActions().isEmpty;
      final dataFresh = lastSync != null && DateTime.now().difference(lastSync).inMinutes < 5;
      if (queueEmpty && dataFresh) {
        return; // Idle sync skip optimization
      }
    }

    // Double-check connectivity before proceeding
    final results = await Connectivity().checkConnectivity();
    if (results.contains(ConnectivityResult.none)) {
      isOnlineNotifier.value = false;
      return;
    }
    isOnlineNotifier.value = true;

    _isSyncing = true;
    isSyncingNotifier.value = true;

    try {
      await _pushQueue();
      await _smartPullSync();
    } finally {
      _recentlyResolvedSyncIds.clear();
      _isSyncing = false;
      isSyncingNotifier.value = false;
      _updatePendingCount();
    }
  }

  /// Update the pending count notifier — called after every sync attempt.
  void _updatePendingCount() {
    try {
      pendingCountNotifier.value = LocalDbService.getPendingActions().length;
    } catch (_) {
      pendingCountNotifier.value = 0;
    }
  }

  // ─── Push Queue ───────────────────────────────────────────────────────────

  /// Push pending sync actions to server in FIFO order.
  ///
  /// Key guarantees:
  ///   - Actions are processed oldest-first (chronological FIFO)
  ///   - Parent records must sync before child records (Party → Entry → Item)
  ///   - On first failure: stop the cycle (preserve ordering integrity)
  ///   - Failed actions have retryCount incremented
  ///   - Actions exceeding maxRetries are abandoned (logged, not deleted)
  ///   - Idempotency key sent with every request (safe to retry)
  Future<void> _pushQueue() async {
    final box = LocalDbService.syncBox;

    // Oldest-first ordering — critical for relational integrity
    final allActions = box.values.toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    final entityActions = allActions.where((a) => !a.endpoint.startsWith('activities/')).toList();
    final activityActions = allActions.where((a) => a.endpoint.startsWith('activities/')).toList();

    await _processActionList(entityActions, box);
    await _processActionList(activityActions, box);
  }

  Future<void> _processActionList(List<SyncAction> actions, Box<SyncAction> box) async {
    for (final action in actions) {
      // Skip: already at max retries (abandoned)
      if (action.isAbandoned) {
        debugPrint('[SyncManager] Skipping abandoned action: ${action.endpoint} (${action.retryCount} retries)');
        continue;
      }

      // Skip: currently in flight (shouldn't happen after crash recovery, but defensive)
      if (action.status == SyncStatus.syncing) continue;

      // Mark as in-flight (persisted so crash recovery works)
      action.status    = SyncStatus.syncing;
      action.isSyncing = true;
      await action.save();

      try {
        await _processAction(action);
        // ✅ Success — remove from queue
        await box.delete(action.id);
        debugPrint('[SyncManager] ✓ ${action.method} ${action.endpoint}');
      } catch (e) {
        if (e.toString().contains('Parent entry not yet synced') ||
            e.toString().contains('Parent party not yet synced')) {
          // ↷ Deferred dependency wait — not a failure.
          // The action was never sent to the server; no retry slot should be consumed.
          // Status reverts to pending so the UI shows it as a normal waiting item,
          // not an error. Next sync cycle will re-evaluate once the parent has a real ID.
          action.status        = SyncStatus.pending;
          action.isSyncing     = false;
          action.failureReason = 'Waiting for parent record to sync first';
          await action.save();
          debugPrint('[SyncManager] ↷ Deferred ${action.endpoint} — parent not yet synced (retryCount unchanged: ${action.retryCount})');
          continue;
        } else if (e is FormatException && (e.message.startsWith('CONFLICT_409:') || e.message.startsWith('CONFLICT_404:') || e.message.startsWith('CONFLICT_400:'))) {
          // 409/404/400 conflicts are unrecoverable (e.g. duplicate POST, stale delete, bad action choice).
          // Abandon this action so it doesn't block the rest of the queue forever.
          action.status        = SyncStatus.conflict;
          action.isSyncing     = false;
          action.retryCount    = SyncAction.maxRetries; // force-abandon
          action.failureReason = e.message.contains(':') ? e.message.split(':').last : 'Conflict detected';
          await action.save();
          debugPrint('[SyncManager] ✗ Conflict (abandoned): ${action.endpoint}: ${action.failureReason}');
          // ⚠ Do NOT break — conflicts are unrecoverable, skip and continue the queue
        } else {
          // ❌ Transient failure — record it, stop processing to preserve ordering
          action.status        = SyncStatus.failed;
          action.isSyncing     = false;
          action.retryCount    += 1;
          action.failureReason = e.toString();
          await action.save();

          debugPrint('[SyncManager] ✗ ${action.method} ${action.endpoint} '
              '— attempt ${action.retryCount}/${SyncAction.maxRetries}: $e');

          if (action.isAbandoned) {
            debugPrint('[SyncManager] ⚠ Action abandoned after ${SyncAction.maxRetries} retries: ${action.endpoint}');
          }

          // Stop on first transient failure in this list — next cycle will retry from here
          break;
        }
      }
    }
  }

  // ─── Process Single Action ────────────────────────────────────────────────

  /// Sends one queued action to the server.
  ///
  /// Handles:
  ///   - UUID → real ID resolution for parent records
  ///   - Multipart upload for jewellery item images
  ///   - Idempotency key header (safe replay on network failure)
  ///   - Local ID update after successful POST (real server ID written back)
  Future<void> _processAction(SyncAction action) async {
    final token = SettingsService.token;
    final headers = <String, String>{
      'Content-Type': 'application/json',
      // Server uses this to de-duplicate retried requests.
      // If the server processed this key before, it returns the existing record.
      'X-Idempotency-Key': action.idempotencyKey,
    };
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Token $token';
    }

    // ── Parse payload ──
    Map<String, dynamic>? payloadMap;
    if (action.payload != null && action.payload!.isNotEmpty) {
      try {
        payloadMap = jsonDecode(action.payload!) as Map<String, dynamic>;
      } catch (e) {
        debugPrint('[SyncManager] Invalid JSON in action — skipping: ${action.endpoint}');
        return; // Skip corrupted action rather than crashing
      }
    }

    // ── Resolve party_sync_id → real party ID for POST entries/ ──
    if (action.endpoint == 'entries/' && payloadMap != null) {
      if (payloadMap.containsKey('party_sync_id')) {
        final p = LocalDbService.partyBox.get(payloadMap['party_sync_id']);
        if (p == null || p.id == null || p.id! <= 0) {
          throw Exception('Parent party not yet synced to server — deferring entry sync');
        }
        payloadMap['party'] = p.id;
        payloadMap.remove('party_sync_id');
      }
    }

    // ── Resolve entry_sync_id → real entry ID for POST payments/ ──
    if (action.endpoint == 'payments/' && payloadMap != null) {
      if (payloadMap.containsKey('entry_sync_id')) {
        final e = LocalDbService.entryBox.get(payloadMap['entry_sync_id']);
        if (e == null || e.id == null || e.id! <= 0) {
          throw Exception('Parent entry not yet synced to server — deferring payment sync');
        }
        payloadMap['entry'] = e.id;
        payloadMap.remove('entry_sync_id');
      }
    }

    // Map invalid frontend ActivityLog actions to valid backend generic choices
    if (action.endpoint == 'activities/' && payloadMap != null && payloadMap.containsKey('action')) {
      final act = payloadMap['action'].toString();
      if (act == 'ADD_ITEM') {
        payloadMap['action'] = 'CREATE';
      } else if (act == 'RELEASE_ITEM' || act == 'EDIT_ITEM') {
        payloadMap['action'] = 'EDIT';
      } else if (act == 'DELETE_ITEM') {
        payloadMap['action'] = 'DELETE';
      } else if (act == 'UPDATE_PROFILE') {
        payloadMap['action'] = 'PROFILE';
      }
    }

    // ── Resolve UUID in endpoint → real integer ID ──
    // e.g. "entries/{syncId}/withdraw/" → "entries/42/withdraw/"
    String endpoint = action.endpoint;
    final uuidRegExp = RegExp(
        r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}');
    if (uuidRegExp.hasMatch(endpoint)) {
      final match = uuidRegExp.firstMatch(endpoint)!.group(0)!;
      int? realId;
      final e = LocalDbService.entryBox.get(match);
      if (e != null && e.id != null && e.id! > 0) realId = e.id;
      if (realId == null) {
        throw Exception('Object not yet synced to server (UUID: $match)');
      }
      endpoint = endpoint.replaceFirst(match, realId.toString());
    }

    final uri = Uri.parse('${ApiService.baseUrl}/$endpoint');

    // ── Execute HTTP request ──
    http.Response response;

    switch (action.method.toUpperCase()) {
      case 'POST':
        if (action.endpoint == 'items/') {
          response = await _postItem(uri, payloadMap ?? {}, token);
        } else {
          final body = payloadMap != null ? jsonEncode(payloadMap) : null;
          response = await http
              .post(uri, headers: headers, body: body)
              .timeout(const Duration(seconds: 15));
        }
        break;

      case 'PATCH':
        final body = payloadMap != null ? jsonEncode(payloadMap) : null;
        response = await http
            .patch(uri, headers: headers, body: body)
            .timeout(const Duration(seconds: 15));
        break;

      case 'DELETE':
        response = await http
            .delete(uri, headers: headers)
            .timeout(const Duration(seconds: 15));
        break;

      default:
        debugPrint('[SyncManager] Unknown method ${action.method} — skipping');
        return;
    }

    // ── Check response ──
    if (response.statusCode == 409) {
      // Parse conflict info if available
      String errMsg = 'Conflict: version mismatch';
      try {
         final body = jsonDecode(response.body);
         if (body['message'] != null) errMsg = body['message'].toString();
      } catch (_) {}
      throw FormatException('CONFLICT_409:$errMsg');
    }

    if (response.statusCode == 404 && action.method == 'PATCH') {
      throw const FormatException('CONFLICT_404:Parent or record deleted on server.');
    }

    if (response.statusCode == 400 && action.method == 'POST') {
      try {
         final body = jsonDecode(response.body) as Map<String, dynamic>;
         if (body.values.any((v) => v.toString().contains('object does not exist'))) {
           throw const FormatException('CONFLICT_404:Parent deleted on server.');
         }
         
         // Only force-abandon 400s for activities if it's a validation error about the action enum
         if (action.endpoint.startsWith('activities/')) {
           final bodyStr = response.body.toLowerCase();
           if (bodyStr.contains('is not a valid choice') || bodyStr.contains('invalid choice')) {
             throw FormatException('CONFLICT_400:Validation error on activity action: ${response.body}');
           }
         }
      } catch (e) {
         if (e is FormatException) rethrow;
      }
    }

    // 404 on DELETE = already deleted on server → treat as success
    final isDeleteNotFound = action.method.toUpperCase() == 'DELETE' &&
        response.statusCode == 404;
    if (!isDeleteNotFound && response.statusCode >= 400) {
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }

    // ── Write back server-assigned IDs after successful POST ──
    if (action.method.toUpperCase() == 'POST' && response.body.isNotEmpty) {
      await _resolveServerIds(action.endpoint, response.body);
    }
  }

  /// Handles multipart POST for jewellery items (may include an image file).
  Future<http.Response> _postItem(
      Uri uri, Map<String, dynamic> map, String? token) async {
    final request = http.MultipartRequest('POST', uri);
    if (token != null && token.isNotEmpty) {
      request.headers['Authorization'] = 'Token $token';
    }

    // Resolve entry_sync_id → real entry ID
    if (map.containsKey('entry_sync_id')) {
      final e = LocalDbService.entryBox.get(map['entry_sync_id']);
      if (e == null || e.id == null || e.id! <= 0) {
        throw Exception('Parent entry not yet synced to server');
      }
      map['entry'] = e.id;
      map.remove('entry_sync_id');
    }

    request.fields['entry']     = map['entry'].toString();
    request.fields['item_type'] = map['item_type']?.toString() ?? '';
    request.fields['name']      = map['name']?.toString() ?? '';
    request.fields['note']      = map['note']?.toString() ?? '';
    if (map['sync_id'] != null) request.fields['sync_id'] = map['sync_id'].toString();
    if (map['weight'] != null && map['weight'].toString().isNotEmpty) {
      request.fields['weight'] = map['weight'].toString();
    }
    if (map['release_status'] != null) request.fields['release_status'] = map['release_status'].toString();
    if (map['release_date'] != null) request.fields['release_date'] = map['release_date'].toString();
    if (map['release_note'] != null) request.fields['release_note'] = map['release_note'].toString();
    if (map['image'] != null && map['image'].toString().isNotEmpty) {
      try {
        request.files.add(
            await http.MultipartFile.fromPath('image', map['image'].toString()));
      } catch (_) {
        // Image no longer on disk — upload without photo
      }
    }

    final streamed = await request.send().timeout(const Duration(seconds: 20));
    return http.Response.fromStream(streamed);
  }

  /// After a successful POST, update the local Hive record with the real
  /// server-assigned integer ID, and cascade the ID to any child records.
  Future<void> _resolveServerIds(String endpoint, String responseBody) async {
    try {
      final data   = jsonDecode(responseBody) as Map<String, dynamic>;
      final newId  = data['id']      as int?;
      final syncId = data['sync_id'] as String?;
      if (newId == null || syncId == null) return;
      
      _recentlyResolvedSyncIds.add(syncId);

      if (endpoint == 'parties/') {
        final p = LocalDbService.partyBox.get(syncId);
        if (p != null) {
          final oldId = p.id;
          p.id = newId;
          await LocalDbService.partyBox.put(syncId, p);
          // Cascade to entries that linked via negative temp ID
          if (oldId != null && oldId < 0) {
            for (final e in LocalDbService.entryBox.values
                .where((e) => e.party == oldId)
                .toList()) {
              e.party = newId;
              await e.save();
            }
          }
        }
      } else if (endpoint == 'entries/') {
        final e = LocalDbService.entryBox.get(syncId);
        if (e != null) {
          final oldId = e.id;
          if (data['sr_number'] != null) e.srNumber = data['sr_number'] as String;
          e.id = newId;
          await LocalDbService.entryBox.put(syncId, e);
          // Cascade to items that linked via negative temp ID
          if (oldId != null && oldId < 0) {
            for (final i in LocalDbService.itemBox.values
                .where((i) => i.entry == oldId)
                .toList()) {
              i.entry = newId;
              await i.save();
            }
            
            // Cascade to payments that linked via negative temp ID
            for (final p in LocalDbService.paymentBox.values
                .where((p) => p.entry == oldId)
                .toList()) {
              p.entry = newId;
              await p.save();
            }
          }
        }
      } else if (endpoint == 'items/') {
        final i = LocalDbService.itemBox.get(syncId);
        if (i != null) {
          i.id = newId;
          // Fix A: resolve parent entry FK from server response so the item
          // remains visible in UI queries (which filter by entry integer ID).
          final serverEntryId = data['entry'] as int?;
          if (serverEntryId != null && serverEntryId > 0) i.entry = serverEntryId;
          // Fix B: sync local version with the server-assigned version immediately
          // after POST. Ensures any subsequent releaseItem() PATCH sends the correct
          // base version. Without this, a migrated/restored item that starts at
          // version > 1 on the server would cause an immediate 409 on first release.
          final serverVersion = data['version'] as int?;
          if (serverVersion != null && serverVersion > i.version) i.version = serverVersion;
          await LocalDbService.itemBox.put(syncId, i);
        }
      } else if (endpoint == 'payments/') {
        final p = LocalDbService.paymentBox.get(syncId);
        if (p != null) {
          p.id = newId;
          // Fix A: resolve parent entry FK so payment remains visible in UI.
          final serverEntryId = data['entry'] as int?;
          if (serverEntryId != null && serverEntryId > 0) p.entry = serverEntryId;
          await LocalDbService.paymentBox.put(syncId, p);
        }
      }
    } catch (e) {
      debugPrint('[SyncManager] _resolveServerIds error: $e');
    }
  }

  // ─── Pull Sync ────────────────────────────────────────────────────────────

  /// Full reconciliation pull from server.
  ///
  /// Per-record rules:
  ///   - Server has record, local MISSING → INSERT (new on another device)
  ///   - Server has record, local EXISTS  → UPDATE fields if server version is newer
  ///   - Server MISSING record, local EXISTS, locally tombstoned → skip (we deleted it)
  ///   - Server MISSING record, local EXISTS, pending queue op → skip (our own unsynced create)
  ///   - Server MISSING record, local EXISTS, no pending op → DELETE locally (another device deleted it)
  Future<void> _smartPullSync() async {
    try {
      // Build set of syncIds/serverIds that have pending queue ops.
      // This protects two classes of records from being overwritten by pull:
      //   A) Records not yet synced: identified by UUID in payload (sync_id) or endpoint.
      //   B) Records already synced but with a pending edit/delete: identified by
      //      integer server ID in endpoint (e.g. "entries/42/", "parties/7/").
      final pendingSyncIds = <String>{};
      final quarantinedSyncIds = <String>{}; // Fix: Separate protection set for abandoned actions
      pendingSyncIds.addAll(_recentlyResolvedSyncIds); // Fix B: Protect newly resolved records
      // Regex for UUID (class A — unsynced records)
      final uuidRx = RegExp(
          r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}');
      // Regex for integer server IDs in endpoints like "entries/42/" (class B)
      final intIdRx = RegExp(r'(?:parties|entries|items|payments)/(\d+)(?:/|$)');

      for (final action in LocalDbService.syncBox.values) {
        final targetSet = action.isAbandoned ? quarantinedSyncIds : pendingSyncIds;

        // ── Class A: extract sync_id / party_sync_id / entry_sync_id from payload ──
        if (action.payload != null) {
          try {
            final m = jsonDecode(action.payload!) as Map<String, dynamic>;
            for (final key in ['sync_id', 'party_sync_id', 'entry_sync_id']) {
              final v = m[key];
              if (v != null) targetSet.add(v.toString());
            }
          } catch (_) {}
        }

        // ── Class A: UUID in endpoint (e.g. "entries/{uuid}/withdraw/") ──
        final uuidMatch = uuidRx.firstMatch(action.endpoint);
        if (uuidMatch != null) targetSet.add(uuidMatch.group(0)!);

        // ── Class B: integer server ID in endpoint (e.g. "entries/42/") ──
        final intMatch = intIdRx.firstMatch(action.endpoint);
        if (intMatch != null) targetSet.add(intMatch.group(1)!);
      }

      final serverParties = await ApiService().fetchParties();
      final serverPartySyncIds = <String>{};

      for (final serverParty in serverParties) {
        serverParty.syncId ??= 'server-${serverParty.id}';
        serverPartySyncIds.add(serverParty.syncId!);

        if (LocalDbService.isTombstoned(serverParty.syncId!)) continue;

        final localParty = LocalDbService.partyBox.get(serverParty.syncId);
        if (localParty == null) {
          await LocalDbService.saveParty(serverParty, isSync: true);
        } else {
          bool dirty = false;
          if (serverParty.id != null && localParty.id != serverParty.id) { localParty.id = serverParty.id; dirty = true; }
          
          final hasPendingOp = pendingSyncIds.contains(localParty.syncId) || 
                               (localParty.id != null && pendingSyncIds.contains(localParty.id.toString()));
          final isQuarantined = quarantinedSyncIds.contains(localParty.syncId) ||
                                (localParty.id != null && quarantinedSyncIds.contains(localParty.id.toString()));
          
          if (!hasPendingOp && !isQuarantined) {
            if (localParty.name != serverParty.name)       { localParty.name = serverParty.name; dirty = true; }
            if (localParty.phone != serverParty.phone)     { localParty.phone = serverParty.phone; dirty = true; }
            if (localParty.address != serverParty.address) { localParty.address = serverParty.address; dirty = true; }
          }
          if (dirty) await localParty.save();
        }

        if (serverParty.id == null) continue;
        final serverEntries = await ApiService().fetchEntries(serverParty.id!);
        final serverEntrySyncIds = <String>{};

        for (final serverEntry in serverEntries) {
          serverEntry.syncId ??= 'server-${serverEntry.id}';
          serverEntrySyncIds.add(serverEntry.syncId!);

          if (LocalDbService.isTombstoned(serverEntry.syncId!)) continue;

          final localEntry = LocalDbService.entryBox.get(serverEntry.syncId);
          if (localEntry == null) {
            await LocalDbService.saveEntry(serverEntry, isSync: true);
          } else {
            bool dirty = false;
            if (serverEntry.id != null && localEntry.id != serverEntry.id) { localEntry.id = serverEntry.id; dirty = true; }
            
            final hasPendingOp = pendingSyncIds.contains(localEntry.syncId) || 
                                 (localEntry.id != null && pendingSyncIds.contains(localEntry.id.toString()));
            final isQuarantined = quarantinedSyncIds.contains(localEntry.syncId) ||
                                  (localEntry.id != null && quarantinedSyncIds.contains(localEntry.id.toString()));
                                 
            if (!hasPendingOp && !isQuarantined) {
              if (localEntry.status != serverEntry.status)                   { localEntry.status = serverEntry.status; dirty = true; }
              if (localEntry.version < serverEntry.version)                  { localEntry.version = serverEntry.version; dirty = true; }
              if (localEntry.closedAt != serverEntry.closedAt)              { localEntry.closedAt = serverEntry.closedAt; dirty = true; }
              if (localEntry.amount != serverEntry.amount)                   { localEntry.amount = serverEntry.amount; dirty = true; }
              if (localEntry.interest != serverEntry.interest)               { localEntry.interest = serverEntry.interest; dirty = true; }
              if (serverEntry.srNumber.isNotEmpty && localEntry.srNumber != serverEntry.srNumber) {
                localEntry.srNumber = serverEntry.srNumber; dirty = true;
              }
            }
            if (dirty) await localEntry.save();
          }

          if (serverEntry.id == null) continue;
          final serverItems = await ApiService().fetchItems(serverEntry.id!);
          final serverItemSyncIds = <String>{};

          for (final serverItem in serverItems) {
            serverItem.syncId ??= 'server-${serverItem.id}';
            serverItemSyncIds.add(serverItem.syncId!);
            if (LocalDbService.isTombstoned(serverItem.syncId!)) continue;
            final localItem = LocalDbService.itemBox.get(serverItem.syncId);
            if (localItem == null) {
              await LocalDbService.saveItem(serverItem, isSync: true);
            } else {
              bool dirty = false;
              if (serverItem.id != null && localItem.id != serverItem.id) { localItem.id = serverItem.id; dirty = true; }
              
              final hasPendingOp = pendingSyncIds.contains(localItem.syncId) || 
                                   (localItem.id != null && pendingSyncIds.contains(localItem.id.toString()));
              final isQuarantined = quarantinedSyncIds.contains(localItem.syncId) ||
                                    (localItem.id != null && quarantinedSyncIds.contains(localItem.id.toString()));
                                   
              if (!hasPendingOp && !isQuarantined) {
                if (localItem.version < serverItem.version)                 { localItem.version = serverItem.version; dirty = true; }
                if (localItem.name != serverItem.name)                      { localItem.name = serverItem.name; dirty = true; }
                if (localItem.note != serverItem.note)                      { localItem.note = serverItem.note; dirty = true; }
                // Fix C: Phase 1 release fields were missing from reconciliation
                // causing remote releases to never sync down to this device.
                if (localItem.releaseStatus != serverItem.releaseStatus)    { localItem.releaseStatus = serverItem.releaseStatus; dirty = true; }
                if (localItem.releaseDate   != serverItem.releaseDate)      { localItem.releaseDate   = serverItem.releaseDate;   dirty = true; }
                if (localItem.releaseNote   != serverItem.releaseNote)      { localItem.releaseNote   = serverItem.releaseNote;   dirty = true; }
              }
              if (dirty) await localItem.save();
            }
          }

          // Remove local items deleted on server
          final entryLocalId = LocalDbService.entryBox.get(serverEntry.syncId!)?.id ?? serverEntry.id ?? -1;
          for (final localItem in LocalDbService.itemBox.values.where((i) => i.entry == entryLocalId).toList()) {
            final itemSyncId = localItem.syncId ?? '';
            if (serverItemSyncIds.contains(itemSyncId)) continue;
            if (LocalDbService.isTombstoned(itemSyncId)) continue;
            if (pendingSyncIds.contains(itemSyncId)) continue;
            if (quarantinedSyncIds.contains(itemSyncId)) continue;
            debugPrint('[SyncManager] Reconcile: removing item $itemSyncId (deleted on server)');
            await localItem.delete();
          }

          // Payments
          final serverPayments = await ApiService().fetchPayments(serverEntry.id!);
          final serverPaymentSyncIds = <String>{};

          for (final serverPayment in serverPayments) {
            serverPayment.syncId ??= 'server-${serverPayment.id}';
            serverPaymentSyncIds.add(serverPayment.syncId!);
            if (LocalDbService.isTombstoned(serverPayment.syncId!)) continue;
            final localPayment = LocalDbService.paymentBox.get(serverPayment.syncId);
            if (localPayment == null) {
              await LocalDbService.savePayment(serverPayment, isSync: true);
            } else {
              bool dirty = false;
              if (serverPayment.id != null && localPayment.id != serverPayment.id) { localPayment.id = serverPayment.id; dirty = true; }
              
              final hasPendingOp = pendingSyncIds.contains(localPayment.syncId) || 
                                   (localPayment.id != null && pendingSyncIds.contains(localPayment.id.toString()));
              final isQuarantined = quarantinedSyncIds.contains(localPayment.syncId) ||
                                    (localPayment.id != null && quarantinedSyncIds.contains(localPayment.id.toString()));
                                   
              if (!hasPendingOp && !isQuarantined) {
                if (localPayment.amount != serverPayment.amount) { localPayment.amount = serverPayment.amount; dirty = true; }
                if (localPayment.note != serverPayment.note) { localPayment.note = serverPayment.note; dirty = true; }
              }
              if (dirty) await localPayment.save();
            }
          }

          // Remove local payments deleted on server
          for (final localPayment in LocalDbService.paymentBox.values.where((p) => p.entry == entryLocalId).toList()) {
            final paymentSyncId = localPayment.syncId ?? '';
            if (serverPaymentSyncIds.contains(paymentSyncId)) continue;
            if (LocalDbService.isTombstoned(paymentSyncId)) continue;
            if (pendingSyncIds.contains(paymentSyncId)) continue;
            if (quarantinedSyncIds.contains(paymentSyncId)) continue;
            debugPrint('[SyncManager] Reconcile: removing payment $paymentSyncId (deleted on server)');
            await localPayment.delete();
          }
        }

        // Remove local entries deleted on server
        final partyLocalId = LocalDbService.partyBox.get(serverParty.syncId!)?.id ?? serverParty.id ?? -1;
        for (final localEntry in LocalDbService.entryBox.values.where((e) => e.party == partyLocalId).toList()) {
          final entrySyncId = localEntry.syncId ?? '';
          if (serverEntrySyncIds.contains(entrySyncId)) continue;
          if (LocalDbService.isTombstoned(entrySyncId)) continue;
          if (pendingSyncIds.contains(entrySyncId)) continue;
          if (quarantinedSyncIds.contains(entrySyncId)) continue;
          debugPrint('[SyncManager] Reconcile: removing entry $entrySyncId (deleted on server)');
          for (final item in LocalDbService.itemBox.values.where((i) => i.entry == (localEntry.id ?? -1)).toList()) {
            await item.delete();
          }
          await localEntry.delete();
        }
      }

      // Remove local parties deleted on server
      for (final localParty in LocalDbService.partyBox.values.toList()) {
        final partySyncId = localParty.syncId ?? '';
        if (serverPartySyncIds.contains(partySyncId)) continue;
        if (LocalDbService.isTombstoned(partySyncId)) continue;
        if (pendingSyncIds.contains(partySyncId)) continue;
        if (quarantinedSyncIds.contains(partySyncId)) continue;
        debugPrint('[SyncManager] Reconcile: removing party $partySyncId (deleted on server)');
        for (final entry in LocalDbService.entryBox.values.where((e) => e.party == (localParty.id ?? -1)).toList()) {
          for (final item in LocalDbService.itemBox.values.where((i) => i.entry == (entry.id ?? -1)).toList()) {
            await item.delete();
          }
          await entry.delete();
        }
        await LocalDbService.partyBox.delete(partySyncId);
      }

      // Fix D: capture the previous sync window BEFORE updating the timestamp,
      // then write the timestamp NOW (after core entities succeed) so that a
      // subsequent failure in the non-critical activities fetch cannot prevent
      // the timestamp from ever advancing.
      final prevSyncFilter = SettingsService.lastSyncedAt?.toIso8601String();
      await SettingsService.setLastSyncedAt(DateTime.now());
      debugPrint('[SyncManager] Pull reconcile complete.');

      // Fetch and overwrite new Activity Logs — non-critical.
      // A failure here does NOT roll back the sync timestamp.
      try {
        final serverActivities = await ApiService().fetchActivities(since: prevSyncFilter);
        for (final log in serverActivities) {
          // Simple overwrite is safe since logs are immutable
          await LocalDbService.activityBox.put(log.syncId, log);
        }
      } catch (e) {
        debugPrint('[SyncManager] Activity log sync failed (non-critical): $e');
      }

    } catch (e) {
      debugPrint('[SyncManager] Pull sync failed: $e — using cached local data.');
    }
  }

  // ─── Public API ───────────────────────────────────────────────────────────

  /// Trigger a full sync manually (e.g., pull-to-refresh, after login).
  Future<void> performFullSync() => _syncAll(isManual: true);

  /// Trigger pull-only sync (e.g., for read-heavy screens).
  Future<void> performFullPullSync() => _smartPullSync();

  /// Return a human-readable summary of the current queue state.
  /// Useful for debug UI in settings screen.
  Map<String, int> getQueueStats() {
    int pending = 0, syncing = 0, failed = 0, abandoned = 0, conflict = 0;
    try {
      for (final action in LocalDbService.syncBox.values) {
        if (action.isAbandoned)                        { abandoned++; }
        else if (action.status == SyncStatus.conflict) { conflict++;  }
        else if (action.status == SyncStatus.syncing)  { syncing++;   }
        else if (action.status == SyncStatus.failed)   { failed++;    }
        else                                           { pending++;   }
      }
    } catch (_) {}
    return {'pending': pending, 'syncing': syncing, 'failed': failed, 'abandoned': abandoned, 'conflict': conflict};
  }

  /// Returns all queued actions in FIFO order (used for diagnostics)
  List<SyncAction> getQueueDrainOrder() {
    final actions = LocalDbService.syncBox.values.toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return actions;
  }
}
