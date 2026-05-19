import 'package:flutter/material.dart';
import '../models/entry.dart';
import '../models/jewellery_item.dart';
import '../services/api_service.dart';
import '../services/local_db_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'add_item_screen.dart';
import 'edit_entry_screen.dart';
import 'withdraw_screen.dart';

class EntryDetailScreen extends StatefulWidget {
  final Entry entry;
  const EntryDetailScreen({super.key, required this.entry});

  @override
  State<EntryDetailScreen> createState() => _EntryDetailScreenState();
}

class _EntryDetailScreenState extends State<EntryDetailScreen> {
  late Entry _entry;
  List<JewelleryItem> _items = [];
  bool _loadingItems = true;

  @override
  void initState() {
    super.initState();
    _entry = widget.entry;
    _loadItems();
  }

  Future<void> _loadItems() async {
    setState(() => _loadingItems = true);

    // LOCAL FIRST: load from Hive by syncId (Bug #4 fix — more reliable than
    // integer ID matching, which breaks after sync updates entry.id).
    final localList = _entry.syncId != null
        ? LocalDbService.getItemsForEntrySyncId(_entry.syncId!)
        : LocalDbService.getItemsForEntry(_entry.id ?? -1);
    if (mounted) {
      setState(() {
        _items = localList;
        _loadingItems = false;
      });
    }

    // THEN: if online and entry is synced, refresh from server and save locally
    final hasRealId = _entry.id != null && _entry.id! > 0;
    final connectivity = await Connectivity().checkConnectivity();
    final isOnline = !connectivity.contains(ConnectivityResult.none);
    if (!isOnline || !hasRealId) return;

    try {
      final serverList = await ApiService().fetchItems(_entry.id!).timeout(const Duration(seconds: 5));
      for (var item in serverList) {
        item.syncId ??= 'server-${item.id}';
        // Bug #15 fix: skip items that were deleted locally (tombstoned)
        if (LocalDbService.isTombstoned(item.syncId)) continue;
        await LocalDbService.saveItem(item, isSync: true);
      }
      // Reload from local (now contains fresh server data)
      if (mounted) {
        final updated = _entry.syncId != null
            ? LocalDbService.getItemsForEntrySyncId(_entry.syncId!)
            : LocalDbService.getItemsForEntry(_entry.id!);
        setState(() => _items = updated);
      }
    } catch (_) {
      // Server unavailable — already showing local data, nothing to do
    }
  }

  Future<void> _deleteItem(JewelleryItem item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Item'),
        content: Text('Delete "${item.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      if (item.syncId != null) {
        await LocalDbService.deleteItem(item);
      }
      _loadItems();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
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

  IconData _statusIcon(String status) {
    switch (status) {
      case 'ACTIVE': return Icons.check_circle;
      case 'OVERDUE': return Icons.warning_amber;
      case 'WITHDRAWN': return Icons.undo;
      case 'CLOSED': return Icons.lock;
      default: return Icons.help_outline;
    }
  }

  bool get _canWithdraw => _entry.status == 'ACTIVE' || _entry.status == 'OVERDUE';
  bool get _canEdit => _entry.status == 'ACTIVE' || _entry.status == 'OVERDUE';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text((_entry.id == null || _entry.id! < 0) ? 'SR: Pending ⟳' : _entry.srNumber),
        actions: [
          if (_canEdit)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: () async {
                final updated = await Navigator.push<Entry>(
                  context,
                  MaterialPageRoute(builder: (_) => EditEntryScreen(entry: _entry)),
                );
                if (updated != null) setState(() => _entry = updated);
              },
            ),
        ],
      ),
      floatingActionButton: (_entry.status == 'ACTIVE' || _entry.status == 'OVERDUE')
          ? FloatingActionButton.extended(
              onPressed: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => AddItemScreen(entry: _entry)),
                );
                if (result == true) _loadItems();
              },
              icon: const Icon(Icons.add),
              label: const Text('Add Item'),
            )
          : null,
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // Status + summary card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(_statusIcon(_entry.status), color: _statusColor(_entry.status), size: 20),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: _statusColor(_entry.status).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _entry.status,
                          style: TextStyle(color: _statusColor(_entry.status), fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 20),
                  _row('Party', _entry.partyName.isNotEmpty ? _entry.partyName : '—'),
                  _row('Amount', '₹${_entry.amount}'),
                  _row('Interest', '${_entry.interest}% per month'),
                  _row('Date', _entry.date),
                  _row('Days Elapsed', '${_entry.computedDaysElapsed} days'),
                  _row('Total Payable', '₹${_entry.computedTotalPayable.toStringAsFixed(2)}', highlight: true),
                  if (_entry.closedAt != null) _row('Closed On', _entry.closedAt!),
                  // Due date row
                  _dueDateRow(),
                  if (_entry.note.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.amber[50],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.notes, size: 16, color: Colors.amber),
                          const SizedBox(width: 6),
                          Expanded(child: Text(_entry.note, style: const TextStyle(fontSize: 13))),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          // Withdraw button
          if (_canWithdraw) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: OutlinedButton.icon(
                onPressed: () async {
                  final updated = await Navigator.push<Entry>(
                    context,
                    MaterialPageRoute(builder: (_) => WithdrawScreen(entry: _entry)),
                  );
                  if (updated != null) setState(() => _entry = updated);
                },
                icon: const Icon(Icons.undo, color: Colors.blue),
                label: const Text('Withdraw Entry', style: TextStyle(color: Colors.blue)),
                style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.blue)),
              ),
            ),
          ],
          const SizedBox(height: 16),
          // Items section
          Text('Items (${_items.length})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 8),
          if (_loadingItems)
            const Center(child: CircularProgressIndicator())
          else if (_items.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('No items added yet.', style: TextStyle(color: Colors.grey)),
              ),
            )
          else
            ...(_items.map((item) => Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: item.itemType == 'Gold'
                      ? Colors.amber[100]
                      : item.itemType == 'Silver'
                          ? Colors.grey[200]
                          : Colors.purple[50],
                  child: Text(
                    item.itemType[0],
                    style: TextStyle(
                      color: item.itemType == 'Gold'
                          ? Colors.amber[800]
                          : item.itemType == 'Silver'
                              ? Colors.grey[700]
                              : Colors.purple,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.itemType),
                    if (item.weight != null) Text('${item.weight} g', style: const TextStyle(fontSize: 12)),
                    if (item.note.isNotEmpty) Text(item.note, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                    if (item.image != null) 
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            '${ApiService.baseUrl.replaceAll('/api', '')}${item.image}',
                            height: 100,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) => const SizedBox(),
                          ),
                        ),
                      ),
                  ],
                ),
                isThreeLine: item.note.isNotEmpty || item.weight != null,
                trailing: _canEdit
                    ? IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                        onPressed: () => _deleteItem(item),
                      )
                    : null,
              ),
            ))),
        ],
      ),
    );
  }

  Widget _dueDateRow() {
    final dueDate = _entry.parsedDueDate;
    final isClosed = _entry.status == 'WITHDRAWN' || _entry.status == 'CLOSED';

    if (dueDate == null) {
      // No due date — show soft hint only when editable
      if (!_canEdit) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Due Date', style: TextStyle(color: Colors.grey[600], fontSize: 13)),
            Text('No deadline set', style: TextStyle(color: Colors.grey[400], fontSize: 13, fontStyle: FontStyle.italic)),
          ],
        ),
      );
    }

    final daysLeft = _entry.daysUntilDue;
    Color badgeColor;
    String badgeText;
    if (isClosed || daysLeft == null) {
      badgeColor = Colors.grey;
      badgeText  = _entry.dueDateDisplay;
    } else if (daysLeft < 0) {
      badgeColor = Colors.red;
      badgeText  = 'Overdue by ${daysLeft.abs()} day${daysLeft.abs() == 1 ? '' : 's'}';
    } else if (daysLeft == 0) {
      badgeColor = Colors.orange;
      badgeText  = 'Due today';
    } else if (daysLeft <= 3) {
      badgeColor = Colors.orange;
      badgeText  = '$daysLeft days left';
    } else {
      badgeColor = Colors.green[700]!;
      badgeText  = '$daysLeft days left';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(children: [
            Icon(Icons.calendar_today_outlined, size: 14, color: Colors.grey[600]),
            const SizedBox(width: 6),
            Text('Due Date', style: TextStyle(color: Colors.grey[600], fontSize: 13)),
          ]),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '${_entry.dueDateDisplay}  ·  $badgeText',
              style: TextStyle(fontSize: 12, color: badgeColor, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value, {bool highlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
          Text(
            value,
            style: TextStyle(
              fontWeight: highlight ? FontWeight.bold : FontWeight.w500,
              fontSize: highlight ? 16 : 13,
              color: highlight ? const Color(0xFF5C35D4) : null,
            ),
          ),
        ],
      ),
    );
  }
}
