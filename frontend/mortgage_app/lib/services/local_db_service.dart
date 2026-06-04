import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/party.dart';
import '../models/entry.dart';
import '../models/jewellery_item.dart';
import '../models/partial_payment.dart';
import '../models/sync_action.dart';
import '../models/activity_log.dart';

class LocalDbService {
  // ─── User Namespace ───────────────────────────────────────────────────────
  // All data boxes are namespaced per user to prevent cross-user data leakage.
  // Global boxes (settings, tombstones) are NOT namespaced.

  static String _namespace = 'default';

  static void setUserNamespace(String username) {
    _namespace = username.isNotEmpty ? username.toLowerCase().trim() : 'default';
  }

  static String get currentNamespace => _namespace;

  // ─── Box Names ────────────────────────────────────────────────────────────

  static String get partyBoxName     => 'parties_$_namespace';
  static String get entryBoxName     => 'entries_$_namespace';
  static String get itemBoxName      => 'items_$_namespace';
  static String get paymentBoxName   => 'payments_$_namespace';
  static String get activityBoxName  => 'activities_$_namespace';
  static String get syncBoxName      => 'sync_queue_$_namespace';
  // Tombstone box is intentionally GLOBAL (shared across users for safety)
  static const String tombstoneBoxName = 'tombstones';
  // Tombstone metadata box: stores label/type for display in Recycle Bin
  // after the entity has been physically deleted from its data box.
  static const String tombstoneMetaBoxName = 'tombstones_meta';

  // ─── Adapter Registration (call once in main.dart) ───────────────────────

  static void registerAdapters() {
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(PartyAdapter());
    if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(EntryAdapter());
    if (!Hive.isAdapterRegistered(3)) Hive.registerAdapter(JewelleryItemAdapter());
    if (!Hive.isAdapterRegistered(4)) Hive.registerAdapter(SyncActionAdapter());
    if (!Hive.isAdapterRegistered(5)) Hive.registerAdapter(PartialPaymentAdapter());
    if (!Hive.isAdapterRegistered(6)) Hive.registerAdapter(ActivityLogAdapter());
  }

  /// Open user-specific data boxes. Call after setUserNamespace().
  static Future<void> openUserBoxes() async {
    if (!Hive.isBoxOpen(partyBoxName)) await Hive.openBox<Party>(partyBoxName);
    if (!Hive.isBoxOpen(entryBoxName)) await Hive.openBox<Entry>(entryBoxName);
    if (!Hive.isBoxOpen(itemBoxName))  await Hive.openBox<JewelleryItem>(itemBoxName);
    if (!Hive.isBoxOpen(paymentBoxName)) await Hive.openBox<PartialPayment>(paymentBoxName);
    if (!Hive.isBoxOpen(activityBoxName)) await Hive.openBox<ActivityLog>(activityBoxName);
    if (!Hive.isBoxOpen(syncBoxName))  await Hive.openBox<SyncAction>(syncBoxName);
  }

  /// Close user-specific data boxes. Call on logout.
  static Future<void> closeUserBoxes() async {
    if (Hive.isBoxOpen(partyBoxName)) await Hive.box<Party>(partyBoxName).close();
    if (Hive.isBoxOpen(entryBoxName)) await Hive.box<Entry>(entryBoxName).close();
    if (Hive.isBoxOpen(itemBoxName))  await Hive.box<JewelleryItem>(itemBoxName).close();
    if (Hive.isBoxOpen(paymentBoxName)) await Hive.box<PartialPayment>(paymentBoxName).close();
    if (Hive.isBoxOpen(activityBoxName)) await Hive.box<ActivityLog>(activityBoxName).close();
    if (Hive.isBoxOpen(syncBoxName))  await Hive.box<SyncAction>(syncBoxName).close();
  }

  /// Global init: registers adapters and opens the tombstone boxes.
  /// Call ONCE in main() before runApp.
  static Future<void> init() async {
    registerAdapters();

    if (!Hive.isBoxOpen(tombstoneBoxName)) {
      await Hive.openBox<int>(tombstoneBoxName);
    }
    if (!Hive.isBoxOpen(tombstoneMetaBoxName)) {
      await Hive.openBox<String>(tombstoneMetaBoxName);
    }

    await _cleanupOldTombstones();
  }

  static Future<void> _cleanupOldTombstones() async {
    final now = DateTime.now();
    final keysToDelete = <String>[];
    for (final syncId in tombstoneMetaBox.keys.cast<String>()) {
      final meta = tombstoneMetaBox.get(syncId);
      if (meta != null && meta.startsWith('{')) {
        try {
          final data = jsonDecode(meta);
          final deletedAt = DateTime.tryParse(data['deletedAt'] ?? '');
          if (deletedAt != null && now.difference(deletedAt).inDays > 60) {
            keysToDelete.add(syncId);
          }
        } catch (_) {}
      }
    }
    for (final k in keysToDelete) {
      await tombstoneMetaBox.delete(k);
      await tombstoneBox.delete(k);
    }
  }

  // ─── Box Getters ──────────────────────────────────────────────────────────

  static Box<Party>           get partyBox     => Hive.box<Party>(partyBoxName);
  static Box<Entry>           get entryBox     => Hive.box<Entry>(entryBoxName);
  static Box<JewelleryItem>   get itemBox      => Hive.box<JewelleryItem>(itemBoxName);
  static Box<PartialPayment>  get paymentBox   => Hive.box<PartialPayment>(paymentBoxName);
  static Box<ActivityLog>     get activityBox  => Hive.box<ActivityLog>(activityBoxName);
  static Box<SyncAction>      get syncBox          => Hive.box<SyncAction>(syncBoxName);
  static Box<int>             get tombstoneBox     => Hive.box<int>(tombstoneBoxName);
  static Box<String>          get tombstoneMetaBox => Hive.box<String>(tombstoneMetaBoxName);

  // ─── Tombstone Helpers ────────────────────────────────────────────────────
  // Tombstones are global: if a record was deleted on this device, it should
  // never be resurrected regardless of which user account is active.

  static Future<void> _addTombstone(
      String syncId, int serverId, {
      String label = '', String type = '', String payload = '',
  }) async {
    await tombstoneBox.put(syncId, serverId);
    if (label.isNotEmpty || type.isNotEmpty || payload.isNotEmpty) {
      final jsonMeta = jsonEncode({
        'type': type,
        'label': label,
        'payload': payload,
        'deletedAt': DateTime.now().toIso8601String(),
      });
      await tombstoneMetaBox.put(syncId, jsonMeta);
    }
  }

  static Future<void> permanentlyDeleteTombstone(String syncId) async {
    await tombstoneBox.delete(syncId);
    await tombstoneMetaBox.delete(syncId);
  }

  static Future<void> restoreRecord(String syncId) async {
    final meta = tombstoneMetaBox.get(syncId);
    if (meta == null || !meta.startsWith('{')) return;

    final data = jsonDecode(meta);
    final type = data['type'];
    final payloadStr = data['payload'] as String?;
    if (payloadStr == null || payloadStr.isEmpty) return;
    
    final payload = jsonDecode(payloadStr);
    final serverId = tombstoneBox.get(syncId) ?? 0;
    
    if (type == 'Entry') {
      final entry = Entry.fromJson(payload);
      final partyId = entry.party;
      final p = partyBox.values.firstWhere((p) => p.id == partyId, orElse: () => Party(id: -999, syncId: '', name: '', phone: '', address: '', defaultInterestRate: 0, note: ''));
      if (p.id == -999) {
        throw Exception('Cannot restore Entry: The parent Party is deleted. Please restore the Party first.');
      }
    }

    bool pendingDeleteCanceled = false;
    final keysToDelete = <dynamic>[];
    if (serverId > 0) {
      final endpointPrefix = type == 'Party' ? 'parties/$serverId/' : type == 'Entry' ? 'entries/$serverId/' : type == 'Item' ? 'items/$serverId/' : 'payments/$serverId/';
      for (final key in syncBox.keys) {
        final action = syncBox.get(key);
        if (action?.method == 'DELETE' && action!.endpoint.contains(endpointPrefix)) {
          keysToDelete.add(key);
          pendingDeleteCanceled = true;
        }
      }
    }
    
    if (keysToDelete.isNotEmpty) await syncBox.deleteAll(keysToDelete);

    if (type == 'Party') {
      await partyBox.put(syncId, Party.fromJson(payload));
    } else if (type == 'Entry') {
      await entryBox.put(syncId, Entry.fromJson(payload));
    } else if (type == 'Item') {
      await itemBox.put(syncId, JewelleryItem.fromJson(payload));
    } else if (type == 'Payment') {
      await paymentBox.put(syncId, PartialPayment.fromJson(payload));
    }

    await permanentlyDeleteTombstone(syncId);

    if (!pendingDeleteCanceled) {
      final endpoint = type == 'Party' ? 'parties/' : type == 'Entry' ? 'entries/' : type == 'Item' ? 'items/' : 'payments/';
      final newPayload = Map<String, dynamic>.from(payload);
      newPayload.remove('id');
      
      if (type == 'Entry') {
        final partyId = payload['party'];
        final parentParty = partyBox.values.firstWhere((p) => p.id == partyId, orElse: () => Party(id: -999, syncId: '', name: '', phone: '', address: '', defaultInterestRate: 0, note: ''));
        newPayload['party_sync_id'] = parentParty.syncId;
      }
      
      await _queueAction('POST', endpoint, newPayload);
    }
  }

  static bool isTombstoned(String? syncId) {
    if (syncId == null) return false;
    return tombstoneBox.containsKey(syncId);
  }

  // ─── Queue Management ─────────────────────────────────────────────────────

  static Future<void> _queueAction(
      String method, String endpoint, Map<String, dynamic>? payload) async {
    final actionId = const Uuid().v4();
    final action = SyncAction(
      id:               actionId,
      method:           method,
      endpoint:         endpoint,
      payload:          payload != null ? jsonEncode(payload) : null,
      timestamp:        DateTime.now(),
      status:           SyncStatus.pending,
      retryCount:       0,
      idempotencyKey:   actionId,
    );
    await syncBox.put(action.id, action);
  }

  /// For offline-only records (no server id): instead of always queueing a new
  /// POST (which creates duplicates), find an existing POST for the same syncId
  /// and update its payload in-place. Only creates a new action if none exists.
  static Future<void> _upsertOfflinePost(
      String endpoint, String? syncId, Map<String, dynamic> payload) async {
    if (syncId != null) {
      for (final key in syncBox.keys) {
        final action = syncBox.get(key);
        if (action == null) continue;
        if (action.method == 'POST' && action.endpoint == endpoint) {
          // Check if this action's payload contains our syncId
          if (action.payload != null) {
            try {
              final map = jsonDecode(action.payload!) as Map<String, dynamic>;
              if (map['sync_id'] == syncId) {
                // Update payload in-place — preserve original timestamp/idempotency key
                action.payload = jsonEncode(payload);
                action.status  = SyncStatus.pending;
                await action.save();
                return; // done — no new action needed
              }
            } catch (_) {}
          }
        }
      }
    }
    // No existing action found — queue a new POST normally
    await _queueAction('POST', endpoint, payload);
  }

  /// Removes all pending queue actions referencing a given syncId UUID.
  /// Used when deleting an offline-created record to clean up orphaned POSTs.
  static Future<void> _cancelQueuedActionsForSyncId(String syncId) async {
    final keysToDelete = <dynamic>[];
    for (final key in syncBox.keys) {
      final action = syncBox.get(key);
      if (action == null) continue;
      if (action.payload != null) {
        try {
          final map = jsonDecode(action.payload!) as Map<String, dynamic>;
          if (map['sync_id'] == syncId ||
              map['party_sync_id'] == syncId ||
              map['entry_sync_id'] == syncId) {
            keysToDelete.add(key);
            continue;
          }
        } catch (_) {}
      }
      if (action.endpoint.contains(syncId)) {
        keysToDelete.add(key);
      }
    }
    if (keysToDelete.isNotEmpty) await syncBox.deleteAll(keysToDelete);
  }

  /// Returns all queued actions that are still pending or failed (not abandoned).
  /// Synced actions are deleted from the queue, so they never appear here.
  static List<SyncAction> getPendingActions() {
    return syncBox.values
        .where((a) => !a.isAbandoned)
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  }

  // ─── Activity Log ────────────────────────────────────────────────────────

  static Future<void> logActivity({
    required String action,
    required String entityType,
    int? entityId,
    String? entitySyncId,
    String entityNameSnapshot = '',
    required String description,
    String? oldValues,
    String? newValues,
    bool isSync = false,
  }) async {
    // Never generate logs during pull-sync to prevent infinite loops / duplicates
    if (isSync) return;

    final log = ActivityLog(
      syncId: const Uuid().v4(),
      action: action,
      entityType: entityType,
      entityId: entityId,
      entitySyncId: entitySyncId,
      entityNameSnapshot: entityNameSnapshot,
      timestamp: DateTime.now(),
      description: description,
      oldValues: oldValues,
      newValues: newValues,
    );

    await activityBox.put(log.syncId, log);
    await _queueAction('POST', 'activities/', log.toJson());
  }

  // ─── Parties ─────────────────────────────────────────────────────────────

  static List<Party> getParties() =>
      partyBox.values.toList().reversed.toList();

  static Future<void> saveParty(Party party, {bool isSync = false}) async {
    final isNew = party.id == null && !partyBox.containsKey(party.syncId);
    final oldParty = partyBox.get(party.syncId);
    
    await partyBox.put(party.syncId, party);
    
    if (!isSync) {
      final hasRealServerId = party.id != null && party.id! > 0;
      final json = party.toJson();

      if (hasRealServerId) {
        // Deduplicate PATCH for server-synced parties
        final endpoint = 'parties/${party.id}/';
        final keysToRemove = <dynamic>[];
        for (final key in syncBox.keys) {
          final action = syncBox.get(key);
          if (action != null && action.method == 'PATCH' && action.endpoint == endpoint) {
            keysToRemove.add(key);
          }
        }
        if (keysToRemove.isNotEmpty) await syncBox.deleteAll(keysToRemove);
        await _queueAction('PATCH', endpoint, json);
      } else {
        // Offline-only: upsert existing POST instead of creating a duplicate
        await _upsertOfflinePost('parties/', party.syncId, json);
      }

      final oldJson = isNew ? null : jsonEncode({
        'name': oldParty?.name, 'phone': oldParty?.phone, 'address': oldParty?.address, 'note': oldParty?.note
      });
      final newJson = isNew ? null : jsonEncode({
        'name': party.name, 'phone': party.phone, 'address': party.address, 'note': party.note
      });
      
      await logActivity(
        action: isNew ? 'CREATE' : 'EDIT',
        entityType: 'PARTY',
        entityId: party.id,
        entitySyncId: party.syncId,
        entityNameSnapshot: party.name,
        description: isNew ? 'Party created' : 'Party updated',
        oldValues: oldJson,
        newValues: newJson,
      );
    }
  }

  static Future<void> deleteParty(String syncId, {bool isSync = false}) async {
    final p = partyBox.get(syncId);
    if (p == null) return;

    final partyId = p.id;
    final partyLabel = p.name;
    final partyDetail = p.phone.isNotEmpty ? p.phone : 'No phone';
    final payload = jsonEncode(p.toJson());

    // Cascade: delete all related entries
    final relatedEntries = entryBox.values.where((e) {
      if (partyId != null && e.party == partyId) return true;
      return false;
    }).toList();

    for (final e in relatedEntries) {
      if (e.syncId != null) {
        await deleteEntry(e, isSync: isSync);
      }
    }

    await partyBox.delete(syncId);

    if (!isSync) {
      final hasServerId = partyId != null && partyId > 0;
      if (hasServerId) {
        await _addTombstone(syncId, partyId,
            label: '$partyLabel|$partyDetail', type: 'Party', payload: payload);
        await _queueAction('DELETE', 'parties/$partyId/', null);
      } else {
        await _cancelQueuedActionsForSyncId(syncId);
        await _addTombstone(syncId, 0,
            label: '$partyLabel|$partyDetail', type: 'Party', payload: payload);
      }
      
      await logActivity(
        action: 'DELETE',
        entityType: 'PARTY',
        entityId: partyId,
        entitySyncId: syncId,
        entityNameSnapshot: partyLabel,
        description: 'Party deleted',
      );
    }
  }

  // ─── Entries ─────────────────────────────────────────────────────────────

  static List<Entry> getEntriesForParty(int partyId) {
    return entryBox.values
        .where((e) => e.party == partyId && e.status != 'DELETED')
        .toList()
        .reversed
        .toList();
  }

  static List<Entry> getAllActiveEntries() {
    return entryBox.values
        .where((e) => e.status == 'ACTIVE' || e.status == 'OVERDUE')
        .toList()
      ..sort((a, b) {
        final dateA = DateTime.tryParse(a.date) ?? DateTime(1970);
        final dateB = DateTime.tryParse(b.date) ?? DateTime(1970);
        return dateB.compareTo(dateA);
      });
  }

  static List<Entry> getRecentEntries({int limit = 5}) {
    final all = entryBox.values.where((e) => e.status != 'DELETED').toList()
      ..sort((a, b) {
        final dateA = DateTime.tryParse(a.date) ?? DateTime(1970);
        final dateB = DateTime.tryParse(b.date) ?? DateTime(1970);
        return dateB.compareTo(dateA);
      });
    return all.take(limit).toList();
  }

  static List<Entry> searchEntries(String query) {
    final lowerQuery = query.toLowerCase();
    return entryBox.values.where((e) {
      if (e.status == 'DELETED') return false;
      return e.srNumber.toLowerCase().contains(lowerQuery) ||
          e.partyName.toLowerCase().contains(lowerQuery);
    }).toList().reversed.toList();
  }

  static Map<String, dynamic> computeStats() {
    int totalEntries = 0, active = 0, overdue = 0, withdrawn = 0, closed = 0;
    double activeAmount = 0, overdueAmount = 0;

    for (final e in entryBox.values) {
      if (e.status == 'DELETED') continue;
      totalEntries++;
      if (e.status == 'ACTIVE') {
        active++;
        activeAmount += double.tryParse(e.amount) ?? 0;
      } else if (e.status == 'OVERDUE') {
        overdue++;
        overdueAmount += double.tryParse(e.amount) ?? 0;
      } else if (e.status == 'WITHDRAWN') {
        withdrawn++;
      } else if (e.status == 'CLOSED') {
        closed++;
      }
    }

    return {
      'total_parties':  partyBox.values.length,
      'total_entries':  totalEntries,
      'active':         active,
      'overdue':        overdue,
      'withdrawn':      withdrawn,
      'closed':         closed,
      'active_amount':  activeAmount,
      'overdue_amount': overdueAmount,
    };
  }

  static Future<void> saveEntry(Entry entry,
      {bool isSync = false, String? partySyncId}) async {
    final isNew = entry.id == null && !entryBox.containsKey(entry.syncId);
    final oldEntry = entryBox.get(entry.syncId);
    
    await entryBox.put(entry.syncId, entry);
    
    if (!isSync) {
      final json = entry.toJson();
      if (partySyncId != null) json['party_sync_id'] = partySyncId;
      final hasRealServerId = entry.id != null && entry.id! > 0;
      
      if (hasRealServerId) {
        // Deduplicate: remove existing PATCH for same entry before adding new one
        final endpoint = 'entries/${entry.id}/';
        final keysToRemove = <dynamic>[];
        for (final key in syncBox.keys) {
          final action = syncBox.get(key);
          if (action != null && action.method == 'PATCH' && action.endpoint == endpoint) {
            keysToRemove.add(key);
          }
        }
        if (keysToRemove.isNotEmpty) await syncBox.deleteAll(keysToRemove);
        await _queueAction('PATCH', endpoint, json);
      } else {
        // Offline-only: upsert existing POST instead of creating a duplicate
        await _upsertOfflinePost('entries/', entry.syncId, json);
      }

      final oldJson = isNew ? null : jsonEncode({
        'amount': oldEntry?.amount, 'interest': oldEntry?.interest, 'status': oldEntry?.status, 'due_date': oldEntry?.dueDate, 'note': oldEntry?.note
      });
      final newJson = isNew ? null : jsonEncode({
        'amount': entry.amount, 'interest': entry.interest, 'status': entry.status, 'due_date': entry.dueDate, 'note': entry.note
      });

      await logActivity(
        action: isNew ? 'CREATE' : 'EDIT',
        entityType: 'ENTRY',
        entityId: entry.id,
        entitySyncId: entry.syncId,
        entityNameSnapshot: '${entry.srNumber} (${entry.partyName})',
        description: isNew ? 'Entry created' : 'Entry updated',
        oldValues: oldJson,
        newValues: newJson,
      );
    }
  }

  static Future<void> deleteEntry(Entry entry, {bool isSync = false}) async {
    final entryId = entry.id;
    final syncId  = entry.syncId;
    final entryLabel = '${entry.srNumber} — ${entry.partyName}';
    final entryDetail = '₹${entry.amount}  ·  ${entry.status}';
    final payload = jsonEncode(entry.toJson());

    // Delete related items
    final relatedItems = itemBox.values
        .where((i) => i.entry == (entryId ?? -1))
        .toList();
    for (final item in relatedItems) {
      await deleteItem(item, isSync: isSync, parentSyncId: syncId);
    }

    // Delete related payments
    final relatedPayments = paymentBox.values
        .where((p) => p.entry == (entryId ?? -1))
        .toList();
    for (final payment in relatedPayments) {
      await deletePayment(payment, isSync: isSync, parentSyncId: syncId);
    }
    
    await entry.delete();

    if (!isSync && syncId != null) {
      final hasServerId = entryId != null && entryId > 0;
      if (hasServerId) {
        await _addTombstone(syncId, entryId,
            label: '$entryLabel|$entryDetail', type: 'Entry', payload: payload);
        await _queueAction('DELETE', 'entries/$entryId/?version=${entry.version}', null);
      } else {
        await _cancelQueuedActionsForSyncId(syncId);
        await _addTombstone(syncId, 0,
            label: '$entryLabel|$entryDetail', type: 'Entry', payload: payload);
      }
      
      await logActivity(
        action: 'DELETE',
        entityType: 'ENTRY',
        entityId: entryId,
        entitySyncId: syncId,
        entityNameSnapshot: '${entry.srNumber} (${entry.partyName})',
        description: 'Entry deleted',
      );
    }
  }

  static Future<void> withdrawEntry(Entry entry) async {
    final entryId = entry.id;
    entry.status   = 'WITHDRAWN';
    entry.closedAt = DateTime.now().toIso8601String().split('T')[0];
    await entryBox.put(entry.syncId, entry);

    if (entryId != null && entryId > 0) {
      await _queueAction('POST', 'entries/$entryId/withdraw/', null);
    } else {
      // Not yet synced — use syncId; SyncManager will resolve to real ID
      await _queueAction('POST', 'entries/${entry.syncId}/withdraw/', null);
    }

    await logActivity(
      action: 'WITHDRAW',
      entityType: 'ENTRY',
      entityId: entry.id,
      entitySyncId: entry.syncId,
      entityNameSnapshot: '${entry.srNumber} (${entry.partyName})',
      description: 'Entry withdrawn',
    );
  }

  // ─── Items ────────────────────────────────────────────────────────────────

  static List<JewelleryItem> getItemsForEntry(int entryId) =>
      itemBox.values.where((i) => i.entry == entryId).toList();

  /// Primary lookup by syncId — stable across the entire lifecycle.
  /// Use this in preference to getItemsForEntry wherever possible.
  static List<JewelleryItem> getItemsForEntrySyncId(String entrySyncId) {
    final entry = entryBox.get(entrySyncId);
    if (entry == null) return [];
    return getItemsForEntry(entry.id ?? -1);
  }

  static Future<void> saveItem(JewelleryItem item,
      {bool isSync = false, String? entrySyncId}) async {
    await itemBox.put(item.syncId, item);
    if (!isSync) {
      final json = item.toJson();
      if (entrySyncId != null) json['entry_sync_id'] = entrySyncId;
      await _queueAction('POST', 'items/', json);
      
      await logActivity(
        action: 'ADD_ITEM',
        entityType: 'ITEM',
        entityId: item.id,
        entitySyncId: item.syncId,
        entityNameSnapshot: item.name,
        description: 'Item added: ${item.name}',
      );
    }
  }

  static Future<void> deleteItem(JewelleryItem item, {bool isSync = false, String? parentSyncId}) async {
    final itemId = item.id;
    final syncId = item.syncId;
    final payload = item.toJson();
    if (parentSyncId != null) payload['entry_sync_id'] = parentSyncId;
    final payloadStr = jsonEncode(payload);

    await item.delete();
    if (!isSync && syncId != null) {
      if (itemId != null && itemId > 0) {
        await _addTombstone(syncId, itemId, label: item.name, type: 'Item', payload: payloadStr);
        await _queueAction('DELETE', 'items/$itemId/?version=${item.version}', null);
      } else {
        await _cancelQueuedActionsForSyncId(syncId);
        await _addTombstone(syncId, 0, label: item.name, type: 'Item', payload: payloadStr);
      }
      
      await logActivity(
        action: 'DELETE_ITEM',
        entityType: 'ITEM',
        entityId: itemId,
        entitySyncId: syncId,
        entityNameSnapshot: item.name,
        description: 'Item deleted',
      );
    }
  }

  static Future<void> saveBusinessSetting(dynamic setting, {bool isSync = false}) async {
    if (!isSync) {
      await _queueAction('PUT', 'settings/', setting.toJson());
    }
  }

  // ─── Partial Payments ───────────────────────────────────────────────────────

  static List<PartialPayment> getPaymentsForEntrySyncId(String entrySyncId) {
    final entry = entryBox.get(entrySyncId);
    if (entry == null) return [];
    return paymentBox.values.where((p) => p.entry == entry.id).toList()
      ..sort((a, b) {
        final dateA = DateTime.tryParse(a.date) ?? DateTime(1970);
        final dateB = DateTime.tryParse(b.date) ?? DateTime(1970);
        return dateA.compareTo(dateB); // chronological
      });
  }

  static Future<void> savePayment(PartialPayment payment, {bool isSync = false, String? entrySyncId}) async {
    await paymentBox.put(payment.syncId, payment);
    if (!isSync) {
      final json = payment.toJson();
      if (entrySyncId != null) json['entry_sync_id'] = entrySyncId;
      await _queueAction('POST', 'payments/', json);
      
      await logActivity(
        action: 'PAYMENT',
        entityType: 'PAYMENT',
        entityId: payment.id,
        entitySyncId: payment.syncId,
        entityNameSnapshot: '₹${payment.amount}',
        description: 'Partial payment added: ₹${payment.amount}',
      );
    }
  }

  static Future<void> deletePayment(PartialPayment payment, {bool isSync = false, String? parentSyncId}) async {
    final paymentId = payment.id;
    final syncId = payment.syncId;
    final payload = payment.toJson();
    if (parentSyncId != null) payload['entry_sync_id'] = parentSyncId;
    final payloadStr = jsonEncode(payload);

    await payment.delete();
    if (!isSync && syncId != null) {
      if (paymentId != null && paymentId > 0) {
        await _addTombstone(syncId, paymentId, label: '₹${payment.amount}', type: 'Payment', payload: payloadStr);
        await _queueAction('DELETE', 'payments/$paymentId/', null);
      } else {
        await _cancelQueuedActionsForSyncId(syncId);
        await _addTombstone(syncId, 0, label: '₹${payment.amount}', type: 'Payment', payload: payloadStr);
      }
    }
  }
}
