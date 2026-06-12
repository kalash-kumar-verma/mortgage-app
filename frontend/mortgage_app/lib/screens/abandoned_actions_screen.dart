import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/sync_action.dart';
import '../services/local_db_service.dart';

class AbandonedActionsScreen extends StatelessWidget {
  const AbandonedActionsScreen({super.key});

  Future<void> _retryAction(SyncAction action) async {
    action.retryCount = 0;
    action.status = SyncStatus.pending;
    await action.save();
  }

  Future<void> _discardAction(BuildContext context, SyncAction action) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Discard Local Record?'),
        content: const Text(
            'This action permanently failed to sync. Discarding it will delete the local record and remove the sync warning.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await action.delete();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Conflict Inbox'),
        backgroundColor: Colors.red[800],
        foregroundColor: Colors.white,
      ),
      body: ValueListenableBuilder<Box<SyncAction>>(
        valueListenable: LocalDbService.syncBox.listenable(),
        builder: (context, box, _) {
          final actions = LocalDbService.getAbandonedActions();

          if (actions.isEmpty) {
            return const Center(
              child: Text(
                'No sync conflicts.',
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
            );
          }

          return ListView.builder(
            itemCount: actions.length,
            padding: const EdgeInsets.all(8),
            itemBuilder: (context, index) {
              final action = actions[index];
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.error, color: Colors.red[700]),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${action.method} ${action.endpoint}',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          Text(
                            action.timestamp.toString().substring(0, 16),
                            style: TextStyle(color: Colors.grey[600], fontSize: 12),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        action.failureReason ?? 'Unknown error',
                        style: const TextStyle(color: Colors.red),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton.icon(
                            icon: const Icon(Icons.delete_outline, color: Colors.red),
                            label: const Text('Discard', style: TextStyle(color: Colors.red)),
                            onPressed: () => _discardAction(context, action),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.refresh),
                            label: const Text('Retry'),
                            onPressed: () => _retryAction(action),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
