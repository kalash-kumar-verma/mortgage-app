import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import '../models/sync_action.dart';
import 'api_service.dart';
import 'local_db_service.dart';
import 'settings_service.dart';

class SyncManager {
  static final SyncManager _instance = SyncManager._internal();
  factory SyncManager() => _instance;
  SyncManager._internal();

  late StreamSubscription<List<ConnectivityResult>> _connectivitySubscription;
  bool _isSyncing = false;
  final ValueNotifier<bool> isSyncingNotifier = ValueNotifier(false);

  void initialize() {
    _connectivitySubscription =
        Connectivity().onConnectivityChanged.listen(_onConnectivityChanged);
    // Purge corrupted queue actions (safety net)
    _purgeInvalidActions();
    // Attempt sync immediately on startup
    _syncAll();
  }

  Future<void> _purgeInvalidActions() async {
    final box = LocalDbService.syncBox;
    final toDelete = <dynamic>[];
    for (final key in box.keys) {
      final action = box.get(key);
      if (action == null) continue;
      if (action.payload == null || action.payload!.isEmpty) continue;
      try {
        jsonDecode(action.payload!);
      } catch (_) {
        toDelete.add(key);
      }
    }
    if (toDelete.isNotEmpty) {
      await box.deleteAll(toDelete);
      debugPrint('[SyncManager] Purged ${toDelete.length} corrupted sync actions.');
    }
  }

  void dispose() {
    _connectivitySubscription.cancel();
  }

  void _onConnectivityChanged(List<ConnectivityResult> result) {
    if (!result.contains(ConnectivityResult.none)) {
      // Came back online — push local changes then pull fresh data
      _syncAll();
    }
  }

  /// Full sync: 1) Push pending local changes → server  2) Pull new server data → local
  Future<void> _syncAll() async {
    if (_isSyncing) return;

    final results = await Connectivity().checkConnectivity();
    if (results.contains(ConnectivityResult.none)) return;

    _isSyncing = true;
    isSyncingNotifier.value = true;

    try {
      await _pushQueue();
      await _smartPullSync();
    } finally {
      _isSyncing = false;
      isSyncingNotifier.value = false;
    }
  }

  /// Push all queued sync actions to the server in chronological order.
  Future<void> _pushQueue() async {
    final box = LocalDbService.syncBox;

    // Process oldest first to maintain relational ordering
    final actions = box.values.toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    for (final action in actions) {
      if (action.isSyncing) continue;

      action.isSyncing = true;
      await action.save();

      try {
        await _processAction(action);
        await box.delete(action.id); // Success — remove from queue
      } catch (e) {
        debugPrint('[SyncManager] Push failed for ${action.endpoint}: $e');
        action.isSyncing = false;
        await action.save();
        break; // Stop on first failure to preserve ordering
      }
    }
  }

  /// Process a single queued action against the server.
  Future<void> _processAction(SyncAction action) async {
    final token = SettingsService.token;
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Token $token';
    }

    // Parse the stored JSON payload
    Map<String, dynamic>? payloadMap;
    if (action.payload != null && action.payload!.isNotEmpty) {
      try {
        payloadMap = jsonDecode(action.payload!) as Map<String, dynamic>;
      } catch (e) {
        debugPrint('[SyncManager] Invalid JSON — skipping ${action.endpoint}');
        return; // Skip corrupted action silently
      }
    }

    // ── Resolve party_sync_id for POST entries/ ──
    if (action.endpoint == 'entries/' && payloadMap != null) {
      if (payloadMap.containsKey('party_sync_id')) {
        final p = LocalDbService.partyBox.get(payloadMap['party_sync_id']);
        if (p == null || p.id == null || p.id! <= 0) {
          throw Exception('Parent party not yet synced to server');
        }
        payloadMap['party'] = p.id;
        payloadMap.remove('party_sync_id');
      }
    }

    // ── UUID Resolution for withdraw endpoints ──
    // e.g.  entries/{syncId}/withdraw/  →  entries/{realId}/withdraw/
    String endpoint = action.endpoint;
    final uuidRegExp = RegExp(
        r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}');
    if (uuidRegExp.hasMatch(endpoint)) {
      final match = uuidRegExp.firstMatch(endpoint)!.group(0)!;
      int? realId;

      // Check entries (withdraw uses entry syncId)
      final e = LocalDbService.entryBox.get(match);
      if (e != null && e.id != null && e.id! > 0) realId = e.id;

      if (realId == null) {
        throw Exception('Object not yet synced to server (UUID: $match)');
      }
      endpoint = endpoint.replaceFirst(match, realId.toString());
    }

    final uri = Uri.parse('${ApiService.baseUrl}/$endpoint');

    http.Response response;

    switch (action.method.toUpperCase()) {
      case 'POST':
        if (action.endpoint == 'items/') {
          // Items may include an image — use multipart
          final request = http.MultipartRequest('POST', uri);
          if (token != null && token.isNotEmpty) {
            request.headers['Authorization'] = 'Token $token';
          }
          final map = payloadMap ?? {};

          // Resolve entry_sync_id to real server ID
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
          if (map['sync_id'] != null) {
            request.fields['sync_id'] = map['sync_id'].toString();
          }
          if (map['weight'] != null && map['weight'].toString().isNotEmpty) {
            request.fields['weight'] = map['weight'].toString();
          }
          if (map['image'] != null && map['image'].toString().isNotEmpty) {
            try {
              request.files.add(
                  await http.MultipartFile.fromPath('image', map['image'].toString()));
            } catch (_) {
              // Image no longer on disk — skip
            }
          }

          final streamed = await request.send().timeout(const Duration(seconds: 15));
          response = await http.Response.fromStream(streamed);
        } else {
          final body = payloadMap != null ? jsonEncode(payloadMap) : null;
          response = await http.post(uri, headers: headers, body: body)
              .timeout(const Duration(seconds: 10));
        }
        break;

      case 'PATCH':
        final body = payloadMap != null ? jsonEncode(payloadMap) : null;
        response = await http.patch(uri, headers: headers, body: body)
            .timeout(const Duration(seconds: 10));
        break;

      case 'DELETE':
        response = await http.delete(uri, headers: headers)
            .timeout(const Duration(seconds: 10));
        break;

      default:
        return;
    }

    if (response.statusCode >= 400) {
      throw Exception('Sync Failed [${response.statusCode}]: ${response.body}');
    }

    // ── After successful POST: update local record with real server ID ──
    if (action.method.toUpperCase() == 'POST' && response.body.isNotEmpty) {
      try {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final newId = data['id'] as int?;
        final syncId = data['sync_id'] as String?;

        if (newId != null && syncId != null) {
          if (action.endpoint == 'parties/') {
            final p = LocalDbService.partyBox.get(syncId);
            if (p != null) {
              final oldId = p.id;
              p.id = newId;
              await LocalDbService.partyBox.put(syncId, p);
              if (oldId != null && oldId < 0) {
                for (final e in LocalDbService.entryBox.values
                    .where((e) => e.party == oldId)
                    .toList()) {
                  e.party = newId;
                  await e.save();
                }
              }
            }
          } else if (action.endpoint == 'entries/') {
            final e = LocalDbService.entryBox.get(syncId);
            if (e != null) {
              final oldId = e.id;
              if (data['sr_number'] != null) {
                e.srNumber = data['sr_number'] as String;
              }
              e.id = newId;
              await LocalDbService.entryBox.put(syncId, e);
              if (oldId != null && oldId < 0) {
                for (final i in LocalDbService.itemBox.values
                    .where((i) => i.entry == oldId)
                    .toList()) {
                  i.entry = newId;
                  await i.save();
                }
              }
            }
          } else if (action.endpoint == 'items/') {
            final i = LocalDbService.itemBox.get(syncId);
            if (i != null) {
              i.id = newId;
              await LocalDbService.itemBox.put(syncId, i);
            }
          }
        }
      } catch (e) {
        debugPrint('[SyncManager] Failed to update local IDs after POST: $e');
      }
    }
  }

  /// Pull sync: Strictly additive — only adds truly NEW records from the server.
  /// Never overwrites local data. Tombstoned records are always skipped.
  Future<void> _smartPullSync() async {
    try {
      final serverParties = await ApiService().fetchParties();

      for (final serverParty in serverParties) {
        serverParty.syncId ??= 'server-${serverParty.id}';

        // TOMBSTONE: This party was deleted locally — never resurrect
        if (LocalDbService.isTombstoned(serverParty.syncId)) continue;

        // Only add if completely absent locally
        final localParty = LocalDbService.partyBox.get(serverParty.syncId);
        if (localParty == null) {
          await LocalDbService.saveParty(serverParty, isSync: true);
        }

        // Pull entries for this party
        if (serverParty.id == null) continue;
        final serverEntries = await ApiService().fetchEntries(serverParty.id!);

        for (final serverEntry in serverEntries) {
          serverEntry.syncId ??= 'server-${serverEntry.id}';

          // TOMBSTONE: This entry was deleted locally — never resurrect
          if (LocalDbService.isTombstoned(serverEntry.syncId)) continue;

          final localEntry = LocalDbService.entryBox.get(serverEntry.syncId);
          if (localEntry == null) {
            await LocalDbService.saveEntry(serverEntry, isSync: true);
          }

          // Pull items for this entry
          if (serverEntry.id == null) continue;
          final serverItems = await ApiService().fetchItems(serverEntry.id!);

          for (final serverItem in serverItems) {
            serverItem.syncId ??= 'server-${serverItem.id}';
            final localItem = LocalDbService.itemBox.get(serverItem.syncId);
            if (localItem == null) {
              await LocalDbService.saveItem(serverItem, isSync: true);
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[SyncManager] Smart pull failed: $e — using cached data');
    }
  }

  /// Force a full sync manually (e.g., called after login)
  Future<void> performFullSync() async => _syncAll();

  /// Legacy alias kept for compatibility
  Future<void> performFullPullSync() async => _smartPullSync();
}
