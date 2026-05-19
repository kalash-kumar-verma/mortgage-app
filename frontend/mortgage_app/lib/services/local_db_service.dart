import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/party.dart';
import '../models/entry.dart';
import '../models/jewellery_item.dart';
import '../models/partial_payment.dart';
import '../models/sync_action.dart';

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
  static String get syncBoxName      => 'sync_queue_$_namespace';
  // Tombstone box is intentionally GLOBAL (shared across users for safety)
  static const String tombstoneBoxName = 'tombstones';

  // ─── Adapter Registration (call once in main.dart) ───────────────────────

  static void registerAdapters() {
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(PartyAdapter());
    if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(EntryAdapter());
    if (!Hive.isAdapterRegistered(3)) Hive.registerAdapter(JewelleryItemAdapter());
    if (!Hive.isAdapterRegistered(4)) Hive.registerAdapter(SyncActionAdapter());
    if (!Hive.isAdapterRegistered(5)) Hive.registerAdapter(PartialPaymentAdapter());
  }

  /// Open user-specific data boxes. Call after setUserNamespace().
  static Future<void> openUserBoxes() async {
    if (!Hive.isBoxOpen(partyBoxName)) await Hive.openBox<Party>(partyBoxName);
    if (!Hive.isBoxOpen(entryBoxName)) await Hive.openBox<Entry>(entryBoxName);
    if (!Hive.isBoxOpen(itemBoxName))  await Hive.openBox<JewelleryItem>(itemBoxName);
    if (!Hive.isBoxOpen(paymentBoxName)) await Hive.openBox<PartialPayment>(paymentBoxName);
    if (!Hive.isBoxOpen(syncBoxName))  await Hive.openBox<SyncAction>(syncBoxName);
  }

  /// Close user-specific data boxes. Call on logout.
  static Future<void> closeUserBoxes() async {
    if (Hive.isBoxOpen(partyBoxName)) await Hive.box<Party>(partyBoxName).close();
    if (Hive.isBoxOpen(entryBoxName)) await Hive.box<Entry>(entryBoxName).close();
    if (Hive.isBoxOpen(itemBoxName))  await Hive.box<JewelleryItem>(itemBoxName).close();
    if (Hive.isBoxOpen(paymentBoxName)) await Hive.box<PartialPayment>(paymentBoxName).close();
    if (Hive.isBoxOpen(syncBoxName))  await Hive.box<SyncAction>(syncBoxName).close();
  }

  /// Global init: registers adapters and opens the tombstone box.
  /// Call ONCE in main() before runApp.
  static Future<void> init() async {
    registerAdapters();
    if (!Hive.isBoxOpen(tombstoneBoxName)) {
      await Hive.openBox<int>(tombstoneBoxName);
    }
  }

  // ─── Box Getters ──────────────────────────────────────────────────────────

  static Box<Party>           get partyBox     => Hive.box<Party>(partyBoxName);
  static Box<Entry>           get entryBox     => Hive.box<Entry>(entryBoxName);
  static Box<JewelleryItem>   get itemBox      => Hive.box<JewelleryItem>(itemBoxName);
  static Box<PartialPayment>  get paymentBox   => Hive.box<PartialPayment>(paymentBoxName);
  static Box<SyncAction>      get syncBox      => Hive.box<SyncAction>(syncBoxName);
  static Box<int>             get tombstoneBox => Hive.box<int>(tombstoneBoxName);

  // ─── Tombstone Helpers ────────────────────────────────────────────────────
  // Tombstones are global: if a record was deleted on this device, it should
  // never be resurrected regardless of which user account is active.

  static Future<void> _addTombstone(String syncId, int serverId) async {
    await tombstoneBox.put(syncId, serverId);
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

  // ─── Parties ─────────────────────────────────────────────────────────────

  static List<Party> getParties() =>
      partyBox.values.toList().reversed.toList();

  static Future<void> saveParty(Party party, {bool isSync = false}) async {
    await partyBox.put(party.syncId, party);
    if (!isSync) {
      await _queueAction('POST', 'parties/', party.toJson());
    }
  }

  static Future<void> deleteParty(String syncId, {bool isSync = false}) async {
    final p = partyBox.get(syncId);
    if (p == null) return;

    final partyId = p.id;

    // Cascade: delete all related entries and their items
    final relatedEntries = entryBox.values.where((e) {
      if (partyId != null && e.party == partyId) return true;
      return false;
    }).toList();

    for (final e in relatedEntries) {
      final entryLocalId = e.id;
      final relatedItems = itemBox.values
          .where((i) => entryLocalId != null && i.entry == entryLocalId)
          .toList();
      for (final i in relatedItems) {
        await i.delete();
      }
      if (e.syncId != null) await _cancelQueuedActionsForSyncId(e.syncId!);
      await e.delete();
    }

    await partyBox.delete(syncId);

    if (!isSync) {
      final hasServerId = partyId != null && partyId > 0;
      if (hasServerId) {
        await _addTombstone(syncId, partyId);
        await _queueAction('DELETE', 'parties/$partyId/', null);
      } else {
        await _cancelQueuedActionsForSyncId(syncId);
        await _addTombstone(syncId, 0);
      }
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
        await _queueAction('POST', 'entries/', json);
      }
    }
  }

  static Future<void> deleteEntry(Entry entry, {bool isSync = false}) async {
    final entryId = entry.id;
    final syncId  = entry.syncId;

    // Delete related items
    final relatedItems = itemBox.values
        .where((i) => i.entry == (entryId ?? -1))
        .toList();
    for (final item in relatedItems) {
      await item.delete();
    }
    await entry.delete();

    if (!isSync && syncId != null) {
      final hasServerId = entryId != null && entryId > 0;
      if (hasServerId) {
        await _addTombstone(syncId, entryId);
        await _queueAction('DELETE', 'entries/$entryId/?version=${entry.version}', null);
      } else {
        await _cancelQueuedActionsForSyncId(syncId);
        await _addTombstone(syncId, 0);
      }
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
    }
  }

  static Future<void> deleteItem(JewelleryItem item, {bool isSync = false}) async {
    final itemId = item.id;
    final syncId = item.syncId;
    await item.delete();
    if (!isSync && syncId != null) {
      if (itemId != null && itemId > 0) {
        await _queueAction('DELETE', 'items/$itemId/?version=${item.version}', null);
      } else {
        await _cancelQueuedActionsForSyncId(syncId);
      }
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
    }
  }

  static Future<void> deletePayment(PartialPayment payment, {bool isSync = false}) async {
    final paymentId = payment.id;
    final syncId = payment.syncId;
    await payment.delete();
    if (!isSync && syncId != null) {
      if (paymentId != null && paymentId > 0) {
        await _queueAction('DELETE', 'payments/$paymentId/', null);
      } else {
        await _cancelQueuedActionsForSyncId(syncId);
      }
    }
  }
}
