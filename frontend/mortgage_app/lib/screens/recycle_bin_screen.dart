import 'dart:convert';
import 'package:flutter/material.dart';
import '../services/local_db_service.dart';
import '../services/settings_service.dart';

/// Shows locally tombstoned (soft-deleted) records.
/// Records here were deleted on this device but may still exist on the server
/// until the DELETE sync operation propagates.
class RecycleBinScreen extends StatefulWidget {
  const RecycleBinScreen({super.key});

  @override
  State<RecycleBinScreen> createState() => _RecycleBinScreenState();
}

class _RecycleBinScreenState extends State<RecycleBinScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<_TombstoneRecord> _records = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _load() {
    setState(() => _loading = true);
    final tombstones = LocalDbService.tombstoneBox;
    final meta       = LocalDbService.tombstoneMetaBox;

    final records = <_TombstoneRecord>[];

    for (final syncId in tombstones.keys.cast<String>()) {
      final serverId  = tombstones.get(syncId) ?? 0;
      final raw       = meta.get(syncId);

      if (raw == null || raw.isEmpty) {
        // Legacy tombstone created before this fix — no display metadata
        // Try to find the record in the live boxes as a fallback
        final liveEntry = LocalDbService.entryBox.get(syncId);
        if (liveEntry != null) {
          records.add(_TombstoneRecord(
            type: 'Entry',
            label: '${liveEntry.srNumber} — ${liveEntry.partyName}',
            detail: '₹${liveEntry.amount}  ·  ${liveEntry.status}',
            syncId: syncId,
            serverId: serverId,
          ));
          continue;
        }
        final liveParty = LocalDbService.partyBox.get(syncId);
        if (liveParty != null) {
          records.add(_TombstoneRecord(
            type: 'Party',
            label: liveParty.name,
            detail: liveParty.phone.isNotEmpty ? liveParty.phone : 'No phone',
            syncId: syncId,
            serverId: serverId,
          ));
        }
        continue;
      }

      String type = 'Unknown';
      String label = syncId;
      String detail = '';
      bool hasPayload = false;

      if (raw.startsWith('{')) {
        try {
          final data = jsonDecode(raw);
          type = data['type'] ?? 'Unknown';
          label = data['label'] ?? syncId;
          detail = data['deletedAt'] != null 
              ? 'Deleted on ${data['deletedAt'].split('T')[0]}' 
              : '';
          hasPayload = data['payload'] != null && data['payload'].isNotEmpty;
        } catch (_) {}
      } else {
        final parts = raw.split('|');
        type = parts.isNotEmpty ? parts[0] : 'Unknown';
        label = parts.length > 1 ? parts[1] : syncId;
        detail = parts.length > 2 ? parts[2] : '';
      }

      records.add(_TombstoneRecord(
        type: type,
        label: label,
        detail: detail,
        syncId: syncId,
        serverId: serverId,
        hasPayload: hasPayload,
      ));
    }

    setState(() {
      _records = records;
      _loading = false;
    });
  }

  List<_TombstoneRecord> get _entryRecords =>
      _records.where((r) => r.type == 'Entry').toList();

  List<_TombstoneRecord> get _partyRecords =>
      _records.where((r) => r.type == 'Party').toList();

  Widget _emptyState(String type) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.delete_sweep_outlined, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text('No deleted $type',
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[500])),
            const SizedBox(height: 8),
            Text('Deleted records appear here until synced.',
                style: TextStyle(fontSize: 13, color: Colors.grey[400]),
                textAlign: TextAlign.center),
          ],
        ),
      );

  Widget _recordTile(_TombstoneRecord r) {
    return Card(
      child: ListTile(
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            r.type == 'Entry' ? Icons.receipt_long_outlined : Icons.person_outline,
            color: Colors.red[400],
            size: 18,
          ),
        ),
        title: Text(r.label,
            style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14)),
        subtitle: Text(r.detail,
            style: TextStyle(fontSize: 12, color: Colors.grey[500])),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (r.hasPayload && SettingsService.role == 'owner')
              IconButton(
                icon: const Icon(Icons.restore, color: Colors.blue),
                tooltip: 'Restore',
                onPressed: () => _handleRestore(r),
              ),
            if (SettingsService.role == 'owner')
              IconButton(
                icon: const Icon(Icons.delete_forever, color: Colors.red),
                tooltip: 'Permanently Delete',
                onPressed: () => _handlePermanentDelete(r),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _handlePermanentDelete(_TombstoneRecord r) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Permanent Delete'),
        content: const Text('This will permanently remove the record from the local recycle bin. Are you sure?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete Forever', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await LocalDbService.permanentlyDeleteTombstone(r.syncId);
      _load();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Permanently deleted from local device')));
    }
  }

  Future<void> _handleRestore(_TombstoneRecord r) async {
    if (r.type == 'Party') {
      final mode = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Restore Party'),
          content: const Text('Do you want to restore only the Party, or the Party and all its deleted child records?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, 'cancel'), child: const Text('Cancel')),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'party_only'),
              child: const Text('Party Only'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'all'),
              child: const Text('Party + Children', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );

      if (mode == null || mode == 'cancel') return;
      
      setState(() => _loading = true);
      try {
        await LocalDbService.restoreRecord(r.syncId);
        
        if (mode == 'all') {
          final metaBox = LocalDbService.tombstoneMetaBox;
          
          final restoredEntryIds = <int>{};
          final restoredEntrySyncIds = <String>{};

          // 1. Restore Entries
          final entrySyncIds = metaBox.keys.cast<String>().toList();
          for (final syncId in entrySyncIds) {
            final meta = metaBox.get(syncId);
            if (meta != null && meta.startsWith('{')) {
              try {
                final data = jsonDecode(meta);
                if (data['type'] == 'Entry' && data['payload'] != null) {
                  final payload = jsonDecode(data['payload']);
                  if (payload['party'] == LocalDbService.partyBox.get(r.syncId)?.id) {
                    await LocalDbService.restoreRecord(syncId);
                    if (payload['id'] != null) restoredEntryIds.add(payload['id']);
                    restoredEntrySyncIds.add(syncId);
                  }
                }
              } catch (_) {}
            }
          }
          
          // 2. Restore Items
          final itemSyncIds = metaBox.keys.cast<String>().toList();
          for (final syncId in itemSyncIds) {
            final meta = metaBox.get(syncId);
            if (meta != null && meta.startsWith('{')) {
              try {
                final data = jsonDecode(meta);
                if (data['type'] == 'Item' && data['payload'] != null) {
                  final payload = jsonDecode(data['payload']);
                  final eId = payload['entry'];
                  final eSyncId = payload['entry_sync_id'];
                  if (restoredEntryIds.contains(eId) || restoredEntrySyncIds.contains(eSyncId)) {
                    await LocalDbService.restoreRecord(syncId);
                  }
                }
              } catch (_) {}
            }
          }
          
          // 3. Restore Payments
          final paymentSyncIds = metaBox.keys.cast<String>().toList();
          for (final syncId in paymentSyncIds) {
            final meta = metaBox.get(syncId);
            if (meta != null && meta.startsWith('{')) {
              try {
                final data = jsonDecode(meta);
                if (data['type'] == 'Payment' && data['payload'] != null) {
                  final payload = jsonDecode(data['payload']);
                  final eId = payload['entry'];
                  final eSyncId = payload['entry_sync_id'];
                  if (restoredEntryIds.contains(eId) || restoredEntrySyncIds.contains(eSyncId)) {
                    await LocalDbService.restoreRecord(syncId);
                  }
                }
              } catch (_) {}
            }
          }
        }
        _load();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Restored successfully')));
      } catch (e) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } else {
      // Entry or other type
      setState(() => _loading = true);
      try {
        await LocalDbService.restoreRecord(r.syncId);
        
        if (r.type == 'Entry') {
          final metaBox = LocalDbService.tombstoneMetaBox;
          final entryServerId = r.serverId;
          
          // 1. Restore Items
          final itemSyncIds = metaBox.keys.cast<String>().toList();
          for (final syncId in itemSyncIds) {
            final meta = metaBox.get(syncId);
            if (meta != null && meta.startsWith('{')) {
              try {
                final data = jsonDecode(meta);
                if (data['type'] == 'Item' && data['payload'] != null) {
                  final payload = jsonDecode(data['payload']);
                  final eId = payload['entry'];
                  final eSyncId = payload['entry_sync_id'];
                  if ((entryServerId > 0 && eId == entryServerId) || eSyncId == r.syncId) {
                    await LocalDbService.restoreRecord(syncId);
                  }
                }
              } catch (_) {}
            }
          }
          
          // 2. Restore Payments
          final paymentSyncIds = metaBox.keys.cast<String>().toList();
          for (final syncId in paymentSyncIds) {
            final meta = metaBox.get(syncId);
            if (meta != null && meta.startsWith('{')) {
              try {
                final data = jsonDecode(meta);
                if (data['type'] == 'Payment' && data['payload'] != null) {
                  final payload = jsonDecode(data['payload']);
                  final eId = payload['entry'];
                  final eSyncId = payload['entry_sync_id'];
                  if ((entryServerId > 0 && eId == entryServerId) || eSyncId == r.syncId) {
                    await LocalDbService.restoreRecord(syncId);
                  }
                }
              } catch (_) {}
            }
          }
        }
        
        _load();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Restored successfully')));
      } catch (e) {
        setState(() => _loading = false);
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Restore Failed'),
            content: Text(e.toString().replaceAll('Exception: ', '')),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
            ],
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recycle Bin'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          indicatorColor: Colors.white,
          tabs: [
            Tab(text: 'Entries (${_entryRecords.length})'),
            Tab(text: 'Parties (${_partyRecords.length})'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _entryRecords.isEmpty
                    ? _emptyState('entries')
                    : ListView(
                        padding: const EdgeInsets.all(12),
                        children: _entryRecords.map(_recordTile).toList(),
                      ),
                _partyRecords.isEmpty
                    ? _emptyState('parties')
                    : ListView(
                        padding: const EdgeInsets.all(12),
                        children: _partyRecords.map(_recordTile).toList(),
                      ),
              ],
            ),
    );
  }
}

class _TombstoneRecord {
  final String type;
  final String label;
  final String detail;
  final String syncId;
  final int serverId;
  final bool hasPayload;

  _TombstoneRecord({
    required this.type,
    required this.label,
    required this.detail,
    required this.syncId,
    required this.serverId,
    this.hasPayload = false,
  });
}
