import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import '../models/sync_action.dart';
import 'api_service.dart';
import 'local_db_service.dart';

class SyncManager {
  static final SyncManager _instance = SyncManager._internal();
  factory SyncManager() => _instance;
  SyncManager._internal();

  late StreamSubscription<List<ConnectivityResult>> _connectivitySubscription;
  bool _isSyncing = false;

  void initialize() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen(_onConnectivityChanged);
    // Initial check
    _syncQueue();
  }

  void dispose() {
    _connectivitySubscription.cancel();
  }

  void _onConnectivityChanged(List<ConnectivityResult> result) {
    if (!result.contains(ConnectivityResult.none)) {
      _syncQueue();
    }
  }

  Future<void> _syncQueue() async {
    if (_isSyncing) return;
    
    final results = await Connectivity().checkConnectivity();
    if (results.contains(ConnectivityResult.none)) return; // Offline

    _isSyncing = true;
    final box = Hive.box<SyncAction>(LocalDbService.syncBoxName);
    
    // Sort by timestamp (oldest first)
    final actions = box.values.toList()..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    for (var action in actions) {
      if (action.isSyncing) continue;
      
      action.isSyncing = true;
      await action.save();

      try {
        await _processAction(action);
        await box.delete(action.id); // Success, remove from queue
      } catch (e) {
        // Failed, retry later
        action.isSyncing = false;
        await action.save();
        break; // Stop syncing on first error to maintain sequence
      }
    }
    
    _isSyncing = false;
  }

  Future<void> _processAction(SyncAction action) async {
    final uri = Uri.parse('${ApiService.baseUrl}/${action.endpoint}');
    final headers = {'Content-Type': 'application/json'};
    
    http.Response response;
    switch (action.method.toUpperCase()) {
      case 'POST':
        response = await http.post(uri, headers: headers, body: action.payload);
        break;
      case 'PATCH':
        response = await http.patch(uri, headers: headers, body: action.payload);
        break;
      case 'DELETE':
        response = await http.delete(uri, headers: headers);
        break;
      default:
        return;
    }

    if (response.statusCode >= 400) {
      throw Exception('Sync Failed: ${response.statusCode}');
    }
    
    // Here we would ideally parse the response to get the newly generated integer ID from Django 
    // and update local Hive records pointing to the syncId to use the new integer ID, 
    // but for simplicity in Phase 4, we assume sync success means the server has it.
  }

  // A method to pull all fresh data from Django into Hive
  Future<void> performFullPullSync() async {
    final results = await Connectivity().checkConnectivity();
    if (results.contains(ConnectivityResult.none)) return;

    try {
      // 1) Fetch and save all parties to Hive
      final parties = await ApiService().fetchParties();
      for (var p in parties) {
        // Use the integer id as the syncId key if no UUID has been assigned
        p.syncId ??= 'server-${p.id}';
        await LocalDbService.saveParty(p, isSync: true);
      }
      
      // 2) Fetch all entries for each party and save to Hive
      for (var p in parties) {
        if (p.id == null) continue;
        final entries = await ApiService().fetchEntries(p.id!);
        for (var e in entries) {
          e.syncId ??= 'server-${e.id}';
          await LocalDbService.saveEntry(e, isSync: true);
        }
      }
    } catch (e) {
      // Ignore failure — app will use cached data
    }
  }
}
