import 'package:flutter/material.dart';
import '../services/local_db_service.dart';

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

    // Collect syncIds from tombstone box
    final tombstonedSyncIds = tombstones.keys.cast<String>().toSet();

    // Find matching entries in Hive that are tombstoned
    final deletedEntries = LocalDbService.entryBox.values
        .where((e) => e.syncId != null && tombstonedSyncIds.contains(e.syncId))
        .toList();

    // Find matching parties in Hive that are tombstoned
    final deletedParties = LocalDbService.partyBox.values
        .where((p) => p.syncId != null && tombstonedSyncIds.contains(p.syncId.toString()))
        .toList();

    final records = <_TombstoneRecord>[];
    for (final e in deletedEntries) {
      records.add(_TombstoneRecord(
        type: 'Entry',
        label: '${e.srNumber} — ${e.partyName}',
        detail: '₹${e.amount}  ·  ${e.status}',
        syncId: e.syncId!,
        serverId: tombstones.get(e.syncId) ?? 0,
      ));
    }
    for (final p in deletedParties) {
      records.add(_TombstoneRecord(
        type: 'Party',
        label: p.name,
        detail: p.phone.isNotEmpty ? p.phone : 'No phone',
        syncId: p.syncId.toString(),
        serverId: tombstones.get(p.syncId.toString()) ?? 0,
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
        trailing: r.serverId > 0
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('Pending server delete',
                    style: TextStyle(fontSize: 10, color: Colors.orange)),
              )
            : Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('Deleted',
                    style: TextStyle(fontSize: 10, color: Colors.green)),
              ),
      ),
    );
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

  const _TombstoneRecord({
    required this.type,
    required this.label,
    required this.detail,
    required this.syncId,
    required this.serverId,
  });
}
