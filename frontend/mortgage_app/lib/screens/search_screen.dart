import 'package:flutter/material.dart';
import '../models/entry.dart';
import '../services/api_service.dart';
import 'entry_detail_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _searchController = TextEditingController();
  List<Entry> _results = [];
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    if (_searchController.text.isEmpty) {
      setState(() { _results = []; _error = null; });
      return;
    }

    setState(() { _loading = true; _error = null; });
    try {
      final list = await ApiService().fetchAllEntries(search: _searchController.text);
      setState(() { _results = list; _loading = false; });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
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
    return Scaffold(
      appBar: AppBar(title: const Text('Global Search')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search SR Number...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    _search();
                  },
                ),
              ),
              onSubmitted: (_) => _search(),
              textInputAction: TextInputAction.search,
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
                    : _results.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.search_off, size: 60, color: Colors.grey[300]),
                                const SizedBox(height: 16),
                                Text(
                                  _searchController.text.isEmpty
                                      ? 'Enter an SR Number to search'
                                      : 'No entries found for "${_searchController.text}"',
                                  style: const TextStyle(color: Colors.grey),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            itemCount: _results.length,
                            itemBuilder: (context, index) {
                              final e = _results[index];
                              return Card(
                                child: ListTile(
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => EntryDetailScreen(entry: e)),
                                  ),
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
                                    ],
                                  ),
                                  subtitle: Text('${e.partyName}\n₹${e.amount}  •  ${e.date}'),
                                  isThreeLine: true,
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}
