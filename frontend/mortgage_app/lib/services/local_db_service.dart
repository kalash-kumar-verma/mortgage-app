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

  static Future<void> init() async {
    Hive.registerAdapter(PartyAdapter());
    Hive.registerAdapter(EntryAdapter());
    Hive.registerAdapter(JewelleryItemAdapter());
    Hive.registerAdapter(SyncActionAdapter());

    await Hive.openBox<Party>(partyBoxName);
    await Hive.openBox<Entry>(entryBoxName);
    await Hive.openBox<JewelleryItem>(itemBoxName);
    await Hive.openBox<SyncAction>(syncBoxName);
  }

  // ─── Queuing Actions ──────────────────────────
  static Future<void> _queueAction(String method, String endpoint, Map<String, dynamic>? payload) async {
    final box = Hive.box<SyncAction>(syncBoxName);
    final action = SyncAction(
      id: const Uuid().v4(),
      method: method,
      endpoint: endpoint,
      payload: payload?.toString(), // simplistic for now; should use jsonEncode in real scenarios
      timestamp: DateTime.now(),
    );
    await box.put(action.id, action);
  }

  // ─── Parties ─────────────────────────────────
  static Box<Party> get partyBox => Hive.box<Party>(partyBoxName);

  static List<Party> getParties() => partyBox.values.toList().reversed.toList();

  static Future<void> saveParty(Party party, {bool isSync = false}) async {
    await partyBox.put(party.syncId, party);
    if (!isSync) {
      await _queueAction('POST', 'parties/', party.toJson());
    }
  }

  static Future<void> deleteParty(String syncId, {bool isSync = false}) async {
    final p = partyBox.get(syncId);
    if (p != null) {
      await partyBox.delete(syncId);
      if (!isSync) {
        // If it was already synced (has integer ID), queue a real delete
        if (p.id != null) {
          await _queueAction('DELETE', 'parties/${p.id}/', null);
        }
      }
    }
  }

  // ─── Entries ─────────────────────────────────
  static Box<Entry> get entryBox => Hive.box<Entry>(entryBoxName);

  static List<Entry> getEntriesForParty(int partyId) {
    return entryBox.values.where((e) => e.party == partyId && e.status != 'DELETED').toList().reversed.toList();
  }

  static Future<void> saveEntry(Entry entry, {bool isSync = false}) async {
    await entryBox.put(entry.syncId, entry);
    if (!isSync) {
      // POST or PATCH depending on if it has an ID
      if (entry.id == null) {
        await _queueAction('POST', 'entries/', entry.toJson());
      } else {
        await _queueAction('PATCH', 'entries/${entry.id}/', entry.toJson());
      }
    }
  }

  // ─── Items ─────────────────────────────────
  static Box<JewelleryItem> get itemBox => Hive.box<JewelleryItem>(itemBoxName);

  static List<JewelleryItem> getItemsForEntry(int entryId) {
    return itemBox.values.where((i) => i.entry == entryId).toList();
  }

  static Future<void> saveItem(JewelleryItem item, {bool isSync = false}) async {
    await itemBox.put(item.syncId, item);
    if (!isSync) {
      await _queueAction('POST', 'items/', item.toJson());
    }
  }
}
