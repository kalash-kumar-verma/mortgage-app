import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/entry.dart';
import '../models/party.dart';
import '../services/local_db_service.dart';
import 'entry_detail_screen.dart';
import 'party_detail_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _searchController = TextEditingController();
  
  // Tab State
  int _searchTypeIndex = 0; // 0 = Entries, 1 = Parties

  // Filter State (Entries only)
  final Set<String> _selectedStatuses = {};
  DateTimeRange? _selectedDateRange;
  
  // Results
  List<Entry> _entryResults = [];
  List<Party> _partyResults = [];
  List<dynamic> _tombstoneResults = []; // Stores basic info for deleted records

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _performSearch();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _performSearch();
  }

  void _performSearch() {
    final query = _searchController.text;
    if (_searchTypeIndex == 0) {
      // Entries
      if (_selectedStatuses.contains('DELETED')) {
        _searchTombstones(query, 'Entry');
      } else {
        setState(() {
          _entryResults = LocalDbService.searchAdvancedEntries(
            query: query,
            statuses: _selectedStatuses.toList(),
            dateRange: _selectedDateRange,
          );
          _tombstoneResults = [];
        });
      }
    } else {
      // Parties
      if (_selectedStatuses.contains('DELETED')) {
        _searchTombstones(query, 'Party');
      } else {
        setState(() {
          _partyResults = LocalDbService.searchAdvancedParties(query);
          _tombstoneResults = [];
        });
      }
    }
  }

  void _searchTombstones(String query, String expectedType) {
    final lowerQuery = query.toLowerCase().trim();
    final tombstones = LocalDbService.tombstoneBox;
    final meta = LocalDbService.tombstoneMetaBox;
    final matches = <dynamic>[];

    for (final syncId in tombstones.keys.cast<String>()) {
      final raw = meta.get(syncId);
      if (raw == null || raw.isEmpty) continue;

      String type = 'Unknown';
      String label = syncId;
      String detail = '';

      if (raw.startsWith('{')) {
        try {
          final data = jsonDecode(raw);
          type = data['type'] ?? 'Unknown';
          label = data['label'] ?? syncId;
          detail = data['deletedAt'] != null 
              ? 'Deleted on ${data['deletedAt'].split('T')[0]}' 
              : '';
        } catch (_) {}
      } else {
        final parts = raw.split('|');
        type = parts.isNotEmpty ? parts[0] : 'Unknown';
        label = parts.length > 1 ? parts[1] : syncId;
        detail = parts.length > 2 ? parts[2] : '';
      }

      if (type != expectedType) continue;

      if (lowerQuery.isNotEmpty && !label.toLowerCase().contains(lowerQuery)) {
        continue;
      }

      // We skip complex Date Range filtering for Tombstones as they lack full metadata
      // unless parsed from payload. For Phase 2, we just return the matches.
      
      matches.add({
        'label': label,
        'detail': detail,
        'syncId': syncId,
      });
    }

    setState(() {
      _tombstoneResults = matches;
      _entryResults = [];
      _partyResults = [];
    });
  }

  Future<void> _pickDateRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDateRange: _selectedDateRange,
    );
    if (range != null) {
      setState(() => _selectedDateRange = range);
      _performSearch();
    }
  }

  void _toggleStatus(String status) {
    setState(() {
      // If switching to DELETED, clear other statuses (DELETED is mutually exclusive)
      if (status == 'DELETED') {
        _selectedStatuses.clear();
        _selectedStatuses.add('DELETED');
      } else {
        if (_selectedStatuses.contains('DELETED')) {
          _selectedStatuses.remove('DELETED');
        }
        if (_selectedStatuses.contains(status)) {
          _selectedStatuses.remove(status);
        } else {
          _selectedStatuses.add(status);
        }
      }
    });
    _performSearch();
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'ACTIVE': return Colors.green;
      case 'OVERDUE': return Colors.orange;
      case 'WITHDRAWN': return Colors.blue;
      case 'CLOSED': return Colors.grey;
      case 'DELETED': return Colors.red;
      default: return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Global Search')),
      body: Column(
        children: [
          // 1. Toggle
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('Entries'), icon: Icon(Icons.receipt_long)),
                ButtonSegment(value: 1, label: Text('Parties'), icon: Icon(Icons.people)),
              ],
              selected: {_searchTypeIndex},
              onSelectionChanged: (set) {
                setState(() => _searchTypeIndex = set.first);
                _performSearch();
              },
            ),
          ),
          
          // 2. Search Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: _searchTypeIndex == 0 ? 'Search SR or Party Name...' : 'Search Name, Mobile...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    _performSearch();
                  },
                ),
              ),
              textInputAction: TextInputAction.search,
            ),
          ),

          // 3. Filters (Entries only, plus DELETED for both)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                if (_searchTypeIndex == 0) ...[
                  FilterChip(
                    label: const Text('Active'),
                    selected: _selectedStatuses.contains('ACTIVE'),
                    onSelected: (_) => _toggleStatus('ACTIVE'),
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    label: const Text('Overdue'),
                    selected: _selectedStatuses.contains('OVERDUE'),
                    onSelected: (_) => _toggleStatus('OVERDUE'),
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    label: const Text('Released'),
                    selected: _selectedStatuses.contains('WITHDRAWN') || _selectedStatuses.contains('CLOSED'),
                    onSelected: (_) {
                      if (_selectedStatuses.contains('WITHDRAWN')) {
                        _selectedStatuses.remove('WITHDRAWN');
                        _selectedStatuses.remove('CLOSED');
                      } else {
                        _selectedStatuses.remove('DELETED');
                        _selectedStatuses.add('WITHDRAWN');
                        _selectedStatuses.add('CLOSED');
                      }
                      setState(() {});
                      _performSearch();
                    },
                  ),
                  const SizedBox(width: 8),
                  ActionChip(
                    label: Text(_selectedDateRange == null ? 'Date Range' : 'Custom Date'),
                    avatar: const Icon(Icons.calendar_today, size: 16),
                    onPressed: _pickDateRange,
                  ),
                  if (_selectedDateRange != null) ...[
                    const SizedBox(width: 8),
                    ActionChip(
                      label: const Icon(Icons.clear, size: 16),
                      onPressed: () {
                        setState(() => _selectedDateRange = null);
                        _performSearch();
                      },
                    ),
                  ],
                  const SizedBox(width: 8),
                ],
                FilterChip(
                  label: const Text('Deleted'),
                  selected: _selectedStatuses.contains('DELETED'),
                  onSelected: (_) => _toggleStatus('DELETED'),
                  selectedColor: Colors.red.withValues(alpha: 0.2),
                ),
              ],
            ),
          ),
          
          const Divider(height: 1),

          // 4. Results
          Expanded(
            child: _buildResults(),
          ),
        ],
      ),
    );
  }

  Widget _buildResults() {
    if (_selectedStatuses.contains('DELETED')) {
      if (_tombstoneResults.isEmpty) return _emptyState();
      return ListView.builder(
        itemCount: _tombstoneResults.length,
        itemBuilder: (context, index) {
          final t = _tombstoneResults[index];
          return ListTile(
            leading: const Icon(Icons.delete, color: Colors.red),
            title: Text(t['label'], style: const TextStyle(decoration: TextDecoration.lineThrough)),
            subtitle: Text(t['detail']),
            trailing: const Text('Recycle Bin'),
          );
        },
      );
    }

    if (_searchTypeIndex == 0) {
      if (_entryResults.isEmpty) return _emptyState();
      return ListView.builder(
        itemCount: _entryResults.length,
        itemBuilder: (context, index) {
          final e = _entryResults[index];
          return Card(
            child: ListTile(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => EntryDetailScreen(entry: e)),
              ),
              title: Row(
                children: [
                  Text((e.id == null || e.id! < 0) ? 'SR: Pending ⟳' : e.srNumber, style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: _statusColor(e.status).withValues(alpha: 0.15),
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
      );
    } else {
      if (_partyResults.isEmpty) return _emptyState();
      return ListView.builder(
        itemCount: _partyResults.length,
        itemBuilder: (context, index) {
          final p = _partyResults[index];
          return Card(
            child: ListTile(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => PartyDetailScreen(party: p)),
              ),
              leading: CircleAvatar(child: Text(p.name.isNotEmpty ? p.name[0].toUpperCase() : '?')),
              title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(p.phone.isNotEmpty ? p.phone : 'No phone'),
              trailing: const Icon(Icons.chevron_right),
            ),
          );
        },
      );
    }
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off, size: 60, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            'No results found',
            style: const TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
