import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/entry.dart';
import '../services/local_db_service.dart';
import 'entry_detail_screen.dart';

/// Shows a filtered list of entries by status or 'ALL'.
/// Fully offline — reads from Hive.
class FilteredEntryListScreen extends StatelessWidget {
  final String title;
  final String? statusFilter; // null = all entries

  const FilteredEntryListScreen({
    super.key,
    required this.title,
    this.statusFilter,
  });

  Color _statusColor(String status) {
    switch (status) {
      case 'ACTIVE':    return Colors.green;
      case 'OVERDUE':   return Colors.orange;
      case 'WITHDRAWN': return Colors.blue;
      case 'CLOSED':    return Colors.grey;
      default:          return Colors.grey;
    }
  }

  String _formatDueDate(Entry e) {
    final d = e.parsedDueDate;
    if (d == null) return '';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.receipt_long_outlined, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            statusFilter != null ? 'No $statusFilter entries' : 'No entries found',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey[500]),
          ),
          const SizedBox(height: 8),
          Text(
            'Entries will appear here once created.',
            style: TextStyle(fontSize: 13, color: Colors.grey[400]),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ValueListenableBuilder<Box<Entry>>(
        valueListenable: LocalDbService.entryBox.listenable(),
        builder: (context, box, _) {
          final all = box.values.toList();
          final filtered = statusFilter == null
              ? all.where((e) => e.status != 'DELETED').toList()
              : all.where((e) => e.status == statusFilter).toList();

          // Sort: active/overdue first by date desc, withdrawn last by date desc
          filtered.sort((a, b) {
            final aPriority = (a.status == 'ACTIVE' || a.status == 'OVERDUE') ? 0 : 1;
            final bPriority = (b.status == 'ACTIVE' || b.status == 'OVERDUE') ? 0 : 1;
            if (aPriority != bPriority) return aPriority.compareTo(bPriority);
            return b.date.compareTo(a.date);
          });

          if (filtered.isEmpty) return _emptyState();

          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            itemCount: filtered.length,
            itemBuilder: (context, index) {
              final e = filtered[index];
              final isPending = e.id == null || e.id! < 0;
              final statusColor = _statusColor(e.status);
              final daysLeft = e.daysUntilDue;
              final dueDateStr = _formatDueDate(e);

              return Card(
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => EntryDetailScreen(entry: e)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                isPending ? 'SR: Pending ⟳' : e.srNumber,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                              decoration: BoxDecoration(
                                color: statusColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(e.status,
                                  style: TextStyle(fontSize: 11, color: statusColor, fontWeight: FontWeight.w600)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(Icons.person_outline, size: 13, color: Colors.grey[500]),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(e.partyName,
                                  style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                            ),
                            Text('₹${e.amount}',
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                          ],
                        ),
                        if (dueDateStr.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(Icons.calendar_today_outlined, size: 12,
                                  color: daysLeft != null && daysLeft < 0 ? Colors.red : Colors.grey[500]),
                              const SizedBox(width: 4),
                              Text(
                                daysLeft == null
                                    ? dueDateStr
                                    : daysLeft < 0
                                        ? '$dueDateStr  ·  Overdue ${daysLeft.abs()}d'
                                        : daysLeft == 0
                                            ? '$dueDateStr  ·  Due today'
                                            : '$dueDateStr  ·  ${daysLeft}d left',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: daysLeft != null && daysLeft <= 0
                                      ? Colors.red
                                      : daysLeft != null && daysLeft <= 3
                                          ? Colors.orange
                                          : Colors.grey[500],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
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
