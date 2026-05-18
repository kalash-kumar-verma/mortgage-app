import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/party.dart';
import '../models/entry.dart';
import '../models/jewellery_item.dart';
import '../models/sync_action.dart';

class LocalDbService {
  static const String partyBoxName = 'parties';
  static const String entryBoxName = 'entries';
  static const String itemBoxName = 'items';
  static const String syncBoxName = 'sync_queue';
  // Tombstone box: maps syncId → deleted server integer ID (or 0 if never synced).
  // Prevents pull sync from ever resurrecting a locally-deleted record.
  static const String tombstoneBoxName = 'tombstones';

  static Future<void> init() async {
    // Idempotent adapter registration — safe to call on hot restart
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(PartyAdapter());
    if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(EntryAdapter());
    if (!Hive.isAdapterRegistered(3)) Hive.registerAdapter(JewelleryItemAdapter());
    if (!Hive.isAdapterRegistered(4)) Hive.registerAdapter(SyncActionAdapter());

    if (!Hive.isBoxOpen(partyBoxName))    await Hive.openBox<Party>(partyBoxName);
    if (!Hive.isBoxOpen(entryBoxName))    await Hive.openBox<Entry>(entryBoxName);
    if (!Hive.isBoxOpen(itemBoxName))     await Hive.openBox<JewelleryItem>(itemBoxName);
    if (!Hive.isBoxOpen(syncBoxName))     await Hive.openBox<SyncAction>(syncBoxName);
    if (!Hive.isBoxOpen(tombstoneBoxName)) await Hive.openBox<int>(tombstoneBoxName);
  }

  // ─── Box Getters ──────────────────────────────
  static Box<Party>          get partyBox     => Hive.box<Party>(partyBoxName);
  static Box<Entry>          get entryBox     => Hive.box<Entry>(entryBoxName);
  static Box<JewelleryItem>  get itemBox      => Hive.box<JewelleryItem>(itemBoxName);
  static Box<SyncAction>     get syncBox      => Hive.box<SyncAction>(syncBoxName);
  static Box<int>            get tombstoneBox => Hive.box<int>(tombstoneBoxName);

  // ─── Tombstone helpers ─────────────────────────
  // A tombstone stores: syncId → server integer ID (0 if never reached server)
  static Future<void> _addTombstone(String syncId, int serverId) async {
    await tombstoneBox.put(syncId, serverId);
  }

  static bool isTombstoned(String? syncId) {
    if (syncId == null) return false;
    return tombstoneBox.containsKey(syncId);
  }

  // ─── Queuing Actions ──────────────────────────
  static Future<void> _queueAction(
      String method, String endpoint, Map<String, dynamic>? payload) async {
    final action = SyncAction(
      id: const Uuid().v4(),
      method: method,
      endpoint: endpoint,
      payload: payload != null ? jsonEncode(payload) : null,
      timestamp: DateTime.now(),
    );
    await syncBox.put(action.id, action);
  }

  /// Removes all pending queue actions for a given endpoint prefix.
  /// Used when deleting an offline-created record (never synced) to clean
  /// up its orphaned POST action.
  static Future<void> _cancelQueuedActionsForSyncId(String syncId) async {
    final keysToDelete = <dynamic>[];
    for (final key in syncBox.keys) {
      final action = syncBox.get(key);
      if (action == null) continue;
      if (action.payload != null) {
        try {
          final map = jsonDecode(action.payload!) as Map<String, dynamic>;
          if (map['sync_id'] == syncId) {
            keysToDelete.add(key);
            continue;
          }
          // Also match party_sync_id / entry_sync_id for child records
          if (map['party_sync_id'] == syncId || map['entry_sync_id'] == syncId) {
            keysToDelete.add(key);
            continue;
          }
        } catch (_) {}
      }
      // Match endpoint containing the syncId UUID directly
      if (action.endpoint.contains(syncId)) {
        keysToDelete.add(key);
      }
    }
    if (keysToDelete.isNotEmpty) await syncBox.deleteAll(keysToDelete);
  }

  // ─── Parties ─────────────────────────────────
  static List<Party> getParties() => partyBox.values.toList().reversed.toList();

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

    // ─── Cascade: physically delete all related entries & items ───
    if (partyId != null) {
      final relatedEntries = entryBox.values.where((e) => e.party == partyId).toList();
      for (final e in relatedEntries) {
        final relatedItems = itemBox.values.where((i) => i.entry == (e.id ?? -1)).toList();
        for (final i in relatedItems) {
          await i.delete();
        }
        await e.delete();
      }
    }

    // ─── Physically delete the party ───
    await partyBox.delete(syncId);

    if (!isSync) {
      final hasServerId = partyId != null && partyId > 0;
      if (hasServerId) {
        // Party was synced to server — tombstone it and queue DELETE with real server ID
        await _addTombstone(syncId, partyId);
        await _queueAction('DELETE', 'parties/$partyId/', null);
      } else {
        // Party was never synced — just cancel its pending POST (no server record exists)
        await _cancelQueuedActionsForSyncId(syncId);
        // Still tombstone it so pull sync won't add it if somehow it gets to server
        await _addTombstone(syncId, 0);
      }
    }
  }

  // ─── Entries ─────────────────────────────────
  static List<Entry> getEntriesForParty(int partyId) {
    return entryBox.values
        .where((e) => e.party == partyId && e.status != 'DELETED')
        .toList()
        .reversed
        .toList();
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
      'total_parties': partyBox.values.length,
      'total_entries': totalEntries,
      'active': active,
      'overdue': overdue,
      'withdrawn': withdrawn,
      'closed': closed,
      'active_amount': activeAmount,
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
        await _queueAction('PATCH', 'entries/${entry.id}/', json);
      } else {
        await _queueAction('POST', 'entries/', json);
      }
    }
  }

  static Future<void> deleteEntry(Entry entry, {bool isSync = false}) async {
    final entryId = entry.id;
    final syncId = entry.syncId;

    // Physically delete all related items
    final relatedItems = itemBox.values.where((i) => i.entry == (entryId ?? -1)).toList();
    for (final item in relatedItems) {
      await item.delete();
    }
    await entry.delete();

    if (!isSync && syncId != null) {
      final hasServerId = entryId != null && entryId > 0;
      if (hasServerId) {
        await _addTombstone(syncId, entryId);
        await _queueAction('DELETE', 'entries/$entryId/', null);
      } else {
        await _cancelQueuedActionsForSyncId(syncId);
        await _addTombstone(syncId, 0);
      }
    }
  }

  static Future<void> withdrawEntry(Entry entry) async {
    final entryId = entry.id;
    entry.status = 'WITHDRAWN';
    entry.closedAt = DateTime.now().toIso8601String().split('T')[0];
    await entryBox.put(entry.syncId, entry);

    if (entryId != null && entryId > 0) {
      // Already synced — use real server ID in endpoint
      await _queueAction('POST', 'entries/$entryId/withdraw/', null);
    } else {
      // Not yet synced — use syncId, SyncManager will resolve it
      await _queueAction('POST', 'entries/${entry.syncId}/withdraw/', null);
    }
  }

  // ─── Items ─────────────────────────────────
  static List<JewelleryItem> getItemsForEntry(int entryId) =>
      itemBox.values.where((i) => i.entry == entryId).toList();

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
        await _queueAction('DELETE', 'items/$itemId/', null);
      } else {
        await _cancelQueuedActionsForSyncId(syncId);
      }
    }
  }
}
