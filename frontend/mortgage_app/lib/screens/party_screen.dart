import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/party.dart';
import '../services/local_db_service.dart';
import '../services/sync_manager.dart';
import 'add_party_screen.dart';
import 'party_detail_screen.dart';

class PartyScreen extends StatefulWidget {
  const PartyScreen({super.key});

  @override
  State<PartyScreen> createState() => _PartyScreenState();
}

class _PartyScreenState extends State<PartyScreen> {
  String _searchQuery = '';
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Push any pending local changes to server, then refresh in background
    SyncManager().performFullSync();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _deleteParty(Party p) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Party'),
        content: Text('Delete ${p.name}? All their entries will also be deleted locally.'),
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
      if (p.syncId != null) {
        await LocalDbService.deleteParty(p.syncId!);
      }
    } catch (err) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Parties')),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const AddPartyScreen()));
        },
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search parties...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
          ),
          Expanded(
            child: ValueListenableBuilder<Box<Party>>(
              valueListenable: LocalDbService.partyBox.listenable(),
              builder: (context, box, _) {
                var parties = box.values.toList().reversed.toList();
                
                if (_searchQuery.isNotEmpty) {
                  parties = parties.where((p) => p.name.toLowerCase().contains(_searchQuery.toLowerCase())).toList();
                }

                if (parties.isEmpty) {
                  return const Center(child: Text('No parties found. Tap + to add.', style: TextStyle(color: Colors.grey)));
                }

                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: 80),
                  itemCount: parties.length,
                  itemBuilder: (context, index) {
                    final p = parties[index];
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: const Color(0xFF5C35D4).withOpacity(0.1),
                          child: Text(
                            p.name[0].toUpperCase(),
                            style: const TextStyle(color: Color(0xFF5C35D4), fontWeight: FontWeight.bold),
                          ),
                        ),
                        title: Row(
                          children: [
                            Expanded(child: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold))),
                            if (p.id == null) // Show sync icon if not synced to server yet
                              const Icon(Icons.cloud_upload_outlined, size: 16, color: Colors.orange),
                          ],
                        ),
                        subtitle: p.phone.isNotEmpty 
                            ? Row(
                                children: [
                                  const Icon(Icons.phone, size: 12, color: Colors.grey),
                                  const SizedBox(width: 4),
                                  Text(p.phone),
                                ],
                              )
                            : null,
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.red),
                          onPressed: () => _deleteParty(p),
                        ),
                        onTap: () {
                          Navigator.push(context, MaterialPageRoute(builder: (_) => PartyDetailScreen(party: p)));
                        },
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
