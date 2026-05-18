import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/party.dart';
import '../models/entry.dart';
import '../services/local_db_service.dart';
import '../services/sync_manager.dart';
import '../models/sync_action.dart';
import 'add_entry_screen.dart';
import 'entry_detail_screen.dart';

class PartyDetailScreen extends StatefulWidget {
  final Party party;
  const PartyDetailScreen({super.key, required this.party});

  @override
  State<PartyDetailScreen> createState() => _PartyDetailScreenState();
}

class _PartyDetailScreenState extends State<PartyDetailScreen> {

  Future<void> _deleteEntry(Entry e) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Entry'),
        content: Text('Delete ${e.srNumber}? All items will also be deleted.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await LocalDbService.deleteEntry(e);
    } catch (err) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err.toString())));
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'ACTIVE': return Colors.green;
      case 'OVERDUE': return Colors.orange;
      case 'WITHDRAWN': return Colors.blue;
      case 'CLOSED': return Colors.grey;
      default: return Colors.grey;
    }
  }

  Widget _emptyEntriesState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long_outlined, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              'No entries yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey[500],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap the + button below to record\nthe first mortgage entry for this customer.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey[400]),
            ),
            const SizedBox(height: 24),
            const Icon(Icons.arrow_downward, color: Color(0xFF5C35D4), size: 28),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.party;
    return Scaffold(
      appBar: AppBar(
        title: Text(p.name),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => AddEntryScreen(party: p)));
        },
        icon: const Icon(Icons.add),
        label: const Text('New Entry'),
      ),
      body: Column(
        children: [
          // Party info card
          Container(
            width: double.infinity,
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF5C35D4).withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF5C35D4).withOpacity(0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (p.phone.isNotEmpty) ...[
                  Row(children: [
                    const Icon(Icons.phone, size: 16, color: Colors.grey),
                    const SizedBox(width: 6),
                    Text(p.phone, style: const TextStyle(fontSize: 14)),
                  ]),
                  const SizedBox(height: 4),
                ],
                if (p.address.isNotEmpty) ...[
                  Row(children: [
                    const Icon(Icons.location_on_outlined, size: 16, color: Colors.grey),
                    const SizedBox(width: 6),
                    Expanded(child: Text(p.address, style: const TextStyle(fontSize: 14))),
                  ]),
                  const SizedBox(height: 4),
                ],
                if (p.defaultInterestRate != null) ...[
                  Row(children: [
                    const Icon(Icons.percent, size: 16, color: Colors.grey),
                    const SizedBox(width: 6),
                    Expanded(child: Text('Custom Rate: ${p.defaultInterestRate}%', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold))),
                  ]),
                  const SizedBox(height: 4),
                ],
                if (p.note.isNotEmpty) ...[
                  Row(children: [
                    const Icon(Icons.notes, size: 16, color: Colors.grey),
                    const SizedBox(width: 6),
                    Expanded(child: Text(p.note, style: TextStyle(fontSize: 13, color: Colors.grey[700]))),
                  ]),
                ],
              ],
            ),
          ),
          
          Expanded(
            child: ValueListenableBuilder<Box<Entry>>(
              valueListenable: LocalDbService.entryBox.listenable(),
              builder: (context, box, _) {
                // If party.id is null (created offline), it can't link effectively in this basic phase 4 setup
                // unless we match by syncId. For now, since entries link via party ID, we assume we need party ID.
                // Wait! If party was created offline, p.id is null.
                // How do entries link to party? Entry has `int party`. It can't be linked until Party has an ID!
                // This is why we needed negative IDs or String syncIds for relationships!
                
                final int partyIdToMatch = p.id ?? -1;
                
                final entries = LocalDbService.getEntriesForParty(partyIdToMatch);

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: Text(
                        'Entries (${entries.length})',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                    ),
                    Expanded(
                      child: entries.isEmpty
                          ? _emptyEntriesState()
                          : ListView.builder(
                            itemCount: entries.length,
                            itemBuilder: (context, index) {
                              final e = entries[index];
                              return Card(
                                child: ListTile(
                                  onTap: () {
                                    Navigator.push(context, MaterialPageRoute(builder: (_) => EntryDetailScreen(entry: e)));
                                  },
                                  title: Row(
                                    children: [
                                      Text(e.srNumber, style: const TextStyle(fontWeight: FontWeight.bold)),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: _statusColor(e.status).withOpacity(0.15),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                          e.status,
                                          style: TextStyle(fontSize: 11, color: _statusColor(e.status), fontWeight: FontWeight.w600),
                                        ),
                                      ),
                                      ValueListenableBuilder<int>(
                                        valueListenable: SyncManager().pendingCountNotifier,
                                        builder: (context, _, __) {
                                          bool hasConflict = false;
                                          bool hasPending = false;
                                          if (e.id == null) hasPending = true;

                                          for (final action in LocalDbService.syncBox.values) {
                                            if (action.isAbandoned) continue;
                                            if ((e.syncId != null && action.endpoint.contains(e.syncId!)) ||
                                                (e.id != null && action.endpoint.contains(e.id.toString()))) {
                                              if (action.status == SyncStatus.conflict) {
                                                hasConflict = true;
                                              } else {
                                                hasPending = true;
                                              }
                                            }
                                          }

                                          if (hasConflict) {
                                            return const Padding(
                                              padding: EdgeInsets.only(left: 8),
                                              child: Icon(Icons.error, size: 14, color: Colors.red),
                                            );
                                          }
                                          if (hasPending) {
                                            return const Padding(
                                              padding: EdgeInsets.only(left: 8),
                                              child: Icon(Icons.cloud_upload, size: 14, color: Colors.blue),
                                            );
                                          }
                                          return const SizedBox.shrink();
                                        },
                                      ),
                                    ],
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('₹${e.amount}  •  ${e.interest}% p.m.'),
                                      Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              '${e.computedDaysElapsed} days  •  Payable: ₹${e.computedTotalPayable.toStringAsFixed(0)}',
                                              style: const TextStyle(fontSize: 12),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (e.hasDueDate && e.daysRemainingLabel.isNotEmpty)
                                        Text(
                                          e.daysRemainingLabel,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: e.dueDateSeverity == 'red'
                                                ? Colors.red
                                                : e.dueDateSeverity == 'orange'
                                                    ? Colors.orange
                                                    : Colors.grey[600],
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                    ],
                                  ),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                                    onPressed: () => _deleteEntry(e),
                                  ),
                                  isThreeLine: true,
                                ),
                              );
                            },
                          ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
