import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/activity_log.dart';
import '../services/local_db_service.dart';
import 'package:intl/intl.dart';

class ActivityHistoryScreen extends StatefulWidget {
  const ActivityHistoryScreen({super.key});

  @override
  State<ActivityHistoryScreen> createState() => _ActivityHistoryScreenState();
}

class _ActivityHistoryScreenState extends State<ActivityHistoryScreen> {
  String _filterAction = 'All'; // All, CREATE, EDIT, DELETE, WITHDRAW, PAYMENT
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  final List<String> _filters = ['All', 'CREATE', 'EDIT', 'DELETE', 'WITHDRAW', 'PAYMENT'];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  IconData _getActionIcon(String action) {
    switch (action) {
      case 'CREATE': return Icons.add_circle_outline;
      case 'EDIT': return Icons.edit_outlined;
      case 'DELETE': return Icons.delete_outline;
      case 'WITHDRAW': return Icons.undo_outlined;
      case 'PAYMENT': return Icons.payments_outlined;
      case 'ADD_ITEM': return Icons.post_add;
      case 'DELETE_ITEM': return Icons.remove_circle_outline;
      default: return Icons.info_outline;
    }
  }

  Color _getActionColor(String action) {
    switch (action) {
      case 'CREATE': return Colors.green;
      case 'EDIT': return Colors.blue;
      case 'DELETE':
      case 'DELETE_ITEM': return Colors.red;
      case 'WITHDRAW': return Colors.orange;
      case 'PAYMENT': return Colors.teal;
      case 'ADD_ITEM': return Colors.purple;
      default: return Colors.grey;
    }
  }

  Widget _buildTimelineItem(ActivityLog log) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _getActionColor(log.action).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(_getActionIcon(log.action), color: _getActionColor(log.action)),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        log.action,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: _getActionColor(log.action),
                        ),
                      ),
                      Text(
                        DateFormat('h:mm a').format(log.timestamp),
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    log.description,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                  ),
                  if (log.entityNameSnapshot.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Ref: ${log.entityNameSnapshot}',
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Activity History'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(110),
          child: Column(
            children: [
              // Search Bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: TextField(
                  controller: _searchController,
                  onChanged: (val) => setState(() => _searchQuery = val.toLowerCase()),
                  decoration: InputDecoration(
                    hintText: 'Search by SR No, Customer, or Details...',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: Colors.grey.shade100,
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(30),
                      borderSide: BorderSide.none,
                    ),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                  ),
                ),
              ),
              // Filter Chips
              SizedBox(
                height: 40,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: _filters.length,
                  itemBuilder: (context, index) {
                    final filter = _filters[index];
                    final isSelected = _filterAction == filter;
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: FilterChip(
                        label: Text(filter == 'All' ? filter : filter.replaceAll('_', ' ')),
                        selected: isSelected,
                        onSelected: (selected) {
                          if (selected) setState(() => _filterAction = filter);
                        },
                        selectedColor: Colors.blue.withValues(alpha: 0.2),
                        checkmarkColor: Colors.blue,
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
      body: ValueListenableBuilder(
        valueListenable: LocalDbService.activityBox.listenable(),
        builder: (context, Box<ActivityLog> box, _) {
          List<ActivityLog> logs = box.values.toList();
          
          // Apply filters
          if (_filterAction != 'All') {
            logs = logs.where((l) => l.action == _filterAction).toList();
          }
          if (_searchQuery.isNotEmpty) {
            logs = logs.where((l) =>
                l.description.toLowerCase().contains(_searchQuery) ||
                l.entityNameSnapshot.toLowerCase().contains(_searchQuery)
            ).toList();
          }

          // Sort newest first
          logs.sort((a, b) => b.timestamp.compareTo(a.timestamp));

          if (logs.isEmpty) {
            return const Center(
              child: Text('No activity found matching your criteria.', style: TextStyle(color: Colors.grey)),
            );
          }

          // Group by Date
          Map<String, List<ActivityLog>> groupedLogs = {};
          for (var log in logs) {
            String dateKey = DateFormat('MMM d, yyyy').format(log.timestamp);
            if (!groupedLogs.containsKey(dateKey)) {
              groupedLogs[dateKey] = [];
            }
            groupedLogs[dateKey]!.add(log);
          }

          return ListView.builder(
            itemCount: groupedLogs.length,
            itemBuilder: (context, index) {
              String dateKey = groupedLogs.keys.elementAt(index);
              List<ActivityLog> dayLogs = groupedLogs[dateKey]!;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 16, top: 16, bottom: 8),
                    child: Text(
                      dateKey,
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey),
                    ),
                  ),
                  ...dayLogs.map(_buildTimelineItem),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
