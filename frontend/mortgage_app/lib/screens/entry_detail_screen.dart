import 'package:flutter/material.dart';
import '../models/entry.dart';
import '../models/jewellery_item.dart';
import '../services/api_service.dart';
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
    try {
      if (_entry.id == null) { setState(() => _loadingItems = false); return; }
      final list = await ApiService().fetchItems(_entry.id!);
      setState(() { _items = list; _loadingItems = false; });
    } catch (e) {
      setState(() => _loadingItems = false);
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
      if (item.id == null) return;
      await ApiService().deleteItem(item.id!);
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
        title: Text(_entry.srNumber),
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
      floatingActionButton: (_entry.status == 'ACTIVE' || _entry.status == 'OVERDUE') && _entry.id != null
          ? FloatingActionButton.extended(
              onPressed: () async {
                final result = await Navigator.push(
                  context, MaterialPageRoute(builder: (_) => AddItemScreen(entryId: _entry.id!)),
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
                  _row('Days Elapsed', '${_entry.daysElapsed} days'),
                  _row('Total Payable', '₹${_entry.totalPayable.toStringAsFixed(2)}', highlight: true),
                  if (_entry.closedAt != null) _row('Closed On', _entry.closedAt!),
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
                            'http://172.16.142.66:8000${item.image}',
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
