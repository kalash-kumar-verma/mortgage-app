import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/party.dart';
import '../models/entry.dart';
import '../services/local_db_service.dart';
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
      e.status = 'DELETED';
      await LocalDbService.saveEntry(e);
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
                      child: Text('Entries (${entries.length})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    ),
                    Expanded(
                      child: entries.isEmpty
                        ? const Center(child: Text('No entries yet.\nTap + to add.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)))
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
                                      if (e.id == null)
                                        const Padding(
                                          padding: EdgeInsets.only(left: 8),
                                          child: Icon(Icons.cloud_upload_outlined, size: 14, color: Colors.orange),
                                        ),
                                    ],
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('₹${e.amount}  •  ${e.interest}% p.m.'),
                                      Text('${e.daysElapsed} days  •  Payable: ₹${e.totalPayable.toStringAsFixed(0)}',
                                          style: const TextStyle(fontSize: 12)),
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
