import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/sync_action.dart';
import '../services/sync_manager.dart';
import '../services/settings_service.dart';
import '../services/local_db_service.dart';
import 'package:hive_flutter/hive_flutter.dart';

class SyncDiagnosticsScreen extends StatefulWidget {
  const SyncDiagnosticsScreen({super.key});

  @override
  State<SyncDiagnosticsScreen> createState() => _SyncDiagnosticsScreenState();
}

class _SyncDiagnosticsScreenState extends State<SyncDiagnosticsScreen> {
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  void _forceSync() async {
    setState(() => _isSyncing = true);
    await SyncManager().performFullSync();
    if (mounted) setState(() => _isSyncing = false);
  }

  void _clearAbandoned() {
    final box = LocalDbService.syncBox;
    final keys = box.values.where((a) => a.isAbandoned).map((a) => a.id).toList();
    if (keys.isNotEmpty) {
      box.deleteAll(keys);
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cleared ${keys.length} abandoned operations')),
      );
    }
  }

  Future<void> _handleConflict(SyncAction action) async {
    final reason = action.failureReason ?? '';
    final isParentDeleted = reason.contains('Parent deleted') || reason.contains('record deleted');
    final isClosed = reason.contains('already closed');

    final serverVersionRegExp = RegExp(r'server is at version (\d+)');
    final match = serverVersionRegExp.firstMatch(reason);
    final serverVersionStr = match?.group(1);
    final serverVersion = serverVersionStr != null ? int.tryParse(serverVersionStr) : null;

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isParentDeleted ? 'Record Deleted' : (isClosed ? 'Record Closed' : 'Version Conflict')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isParentDeleted
                  ? 'The parent record was deleted on the server.'
                  : (isClosed ? 'This record is already withdrawn/closed and cannot be edited.' : 'Another device has edited this entry since you last synced.'),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text('Action: ${action.method} ${action.endpoint}'),
            const SizedBox(height: 8),
            Text(reason),
            const SizedBox(height: 16),
            const Text('How would you like to resolve this?'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          if (isParentDeleted)
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.blue),
              onPressed: () async {
                // Restore parent: we re-queue the parent for creation if it exists locally
                await _restoreParentAndRetry(action);
                if (mounted) Navigator.pop(ctx);
              },
              child: const Text('Restore Parent & Retry'),
            ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () async {
              // Discard child operation
              await LocalDbService.syncBox.delete(action.id);
              if (mounted) {
                Navigator.pop(ctx);
                _forceSync();
              }
            },
            child: Text(isParentDeleted || isClosed ? 'Discard Local Edit' : 'Use Server Version'),
          ),
          if (!isParentDeleted && !isClosed && serverVersion != null)
            ElevatedButton(
              onPressed: () async {
                // Keep mine -> Update version in payload and retry
                try {
                  final payload = jsonDecode(action.payload ?? '{}') as Map<String, dynamic>;
                  payload['version'] = serverVersion;
                  action.payload = jsonEncode(payload);
                  action.status = SyncStatus.pending;
                  action.failureReason = null;
                  await action.save();
                  if (mounted) {
                    Navigator.pop(ctx);
                    _forceSync();
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error resolving conflict: $e')),
                    );
                  }
                }
              },
              child: const Text('Keep Mine (Overwrite Server)'),
            ),
        ],
      ),
    );
    setState(() {}); // Refresh list
  }

  Future<void> _restoreParentAndRetry(SyncAction action) async {
    // If it's an entry or item, we must find the parent and queue a POST.
    // For simplicity, we can trigger a full local save for the parent which queues the POST.
    try {
      final payload = jsonDecode(action.payload ?? '{}') as Map<String, dynamic>;
      
      if (action.endpoint == 'entries/' || action.endpoint.startsWith('entries/')) {
        // Parent is a Party
        final partyIdStr = payload['party_sync_id'] ?? payload['party'];
        if (partyIdStr != null) {
          final p = LocalDbService.partyBox.values.firstWhere((p) => p.syncId == partyIdStr || p.id.toString() == partyIdStr.toString());
          // Queue party POST
          await LocalDbService.saveParty(p, isSync: false);
        }
      } else if (action.endpoint == 'items/' || action.endpoint.startsWith('items/')) {
        // Parent is an Entry
        final entryIdStr = payload['entry_sync_id'] ?? payload['entry'];
        if (entryIdStr != null) {
          final e = LocalDbService.entryBox.values.firstWhere((e) => e.syncId == entryIdStr || e.id.toString() == entryIdStr.toString());
          await LocalDbService.saveEntry(e, isSync: false, partySyncId: e.party.toString());
        }
      }
      
      // Now set the child action back to pending
      action.status = SyncStatus.pending;
      action.failureReason = null;
      await action.save();
      _forceSync();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not restore parent: $e')));
    }
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} hrs ago';
    return '${diff.inDays} days ago';
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Box<SyncAction>>(
      valueListenable: LocalDbService.syncBox.listenable(),
      builder: (context, box, _) {
        final stats = SyncManager().getQueueStats();
        final actions = SyncManager().getQueueDrainOrder();
        final lastSynced = SettingsService.lastSyncedAt;
        
        // Determine health state
        Color healthColor = Colors.green;
        String healthText = 'Healthy';
        IconData healthIcon = Icons.check_circle;
        
        if (stats['conflict']! > 0) {
          healthColor = Colors.red;
          healthText = 'Conflicts detected';
          healthIcon = Icons.error;
        } else if (stats['failed']! > 0 || stats['abandoned']! > 0) {
          healthColor = Colors.orange;
          healthText = 'Errors in queue';
          healthIcon = Icons.warning;
        } else if (stats['pending']! > 0 || stats['syncing']! > 0) {
          healthColor = Colors.blue;
          healthText = 'Syncing...';
          healthIcon = Icons.sync;
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('Sync Diagnostics'),
            backgroundColor: Colors.grey[900],
            foregroundColor: Colors.white,
          ),
          body: Column(
            children: [
          // Health Banner
          Container(
            color: healthColor.withValues(alpha: 0.1),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            child: Row(
              children: [
                Icon(healthIcon, color: healthColor),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(healthText, style: TextStyle(fontWeight: FontWeight.bold, color: healthColor)),
                      Text(
                        lastSynced != null ? 'Last synced: ${_timeAgo(lastSynced)}' : 'Never synced',
                        style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                      ),
                    ],
                  ),
                ),
                if (_isSyncing)
                  const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
              ],
            ),
          ),
          
          // Queue Summary
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _statColumn('Pending', stats['pending']!, Colors.blue),
                _statColumn('Failed', stats['failed']!, Colors.orange),
                _statColumn('Conflict', stats['conflict']!, Colors.red),
                _statColumn('Abandoned', stats['abandoned']!, Colors.grey),
              ],
            ),
          ),

          // Actions
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isSyncing ? null : _forceSync,
                    icon: const Icon(Icons.sync),
                    label: const Text('Force Sync'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: stats['abandoned']! > 0 ? _clearAbandoned : null,
                    icon: const Icon(Icons.delete_sweep),
                    label: const Text('Clear Abandoned'),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 32),
          
          // Operation History
          Expanded(
            child: actions.isEmpty
                ? const Center(child: Text('Queue is empty'))
                : ListView.builder(
                    itemCount: actions.length,
                    itemBuilder: (context, index) {
                      final a = actions[index];
                      return _buildActionTile(a);
                    },
                  ),
          ),
        ],
      ),
    );
      },
    );
  }

  Widget _statColumn(String label, int value, Color color) {
    return Column(
      children: [
        Text(value.toString(), style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }

  Widget _buildActionTile(SyncAction action) {
    Color statusColor;
    IconData statusIcon;
    
    switch (action.status) {
      case SyncStatus.conflict:
        statusColor = Colors.red;
        statusIcon = Icons.error_outline;
        break;
      case SyncStatus.failed:
        statusColor = Colors.orange;
        statusIcon = Icons.warning_amber;
        break;
      case SyncStatus.syncing:
        statusColor = Colors.blue;
        statusIcon = Icons.sync;
        break;
      default:
        statusColor = Colors.grey;
        statusIcon = Icons.schedule;
        if (action.isAbandoned) {
          statusColor = Colors.black54;
          statusIcon = Icons.block;
        }
    }

    Color methodColor = Colors.grey;
    if (action.method == 'POST') methodColor = Colors.green;
    if (action.method == 'PATCH') methodColor = Colors.orange;
    if (action.method == 'DELETE') methodColor = Colors.red;

    return ListTile(
      leading: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: methodColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(action.method, style: TextStyle(color: methodColor, fontWeight: FontWeight.bold, fontSize: 11)),
      ),
      title: Text(action.endpoint, style: const TextStyle(fontSize: 14)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(statusIcon, size: 14, color: statusColor),
              const SizedBox(width: 4),
              Text(
                action.isAbandoned ? 'Abandoned' : action.status.toUpperCase(),
                style: TextStyle(fontSize: 12, color: statusColor, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 12),
              Text('Retries: ${action.retryCount}/${SyncAction.maxRetries}', style: const TextStyle(fontSize: 12)),
            ],
          ),
          if (action.failureReason != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(action.failureReason!, style: const TextStyle(fontSize: 12, color: Colors.red)),
            ),
        ],
      ),
      trailing: Text(_timeAgo(action.timestamp), style: const TextStyle(fontSize: 11, color: Colors.grey)),
      onTap: action.status == SyncStatus.conflict ? () => _handleConflict(action) : null,
      tileColor: action.status == SyncStatus.conflict ? Colors.red.withValues(alpha: 0.05) : null,
    );
  }
}
