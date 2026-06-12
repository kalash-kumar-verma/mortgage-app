import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/entry.dart';
import '../models/jewellery_item.dart';
import '../widgets/conflict_badge.dart';
import '../models/partial_payment.dart';
import '../services/api_service.dart';
import '../services/local_db_service.dart';
import 'add_item_screen.dart';
import 'edit_entry_screen.dart';
import 'withdraw_screen.dart';
import 'receipt_screen.dart';
import 'partial_payment_dialog.dart';
import 'package:intl/intl.dart';

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
  List<PartialPayment> _payments = [];
  bool _loadingPayments = true;
  bool _withdrawing = false; // guard against double-tap

  late final ValueListenable<Box<JewelleryItem>> _itemsListenable;
  late final ValueListenable<Box<PartialPayment>> _paymentsListenable;
  late final ValueListenable<Box<Entry>> _entryListenable;

  @override
  void initState() {
    super.initState();
    _entry = widget.entry;
    _loadItems();
    _loadPayments();
    
    _itemsListenable = LocalDbService.itemBox.listenable();
    _paymentsListenable = LocalDbService.paymentBox.listenable();
    _entryListenable = LocalDbService.entryBox.listenable();
    
    _itemsListenable.addListener(_loadItems);
    _paymentsListenable.addListener(_loadPayments);
    _entryListenable.addListener(_onEntryChanged);
  }

  void _onEntryChanged() {
    if (mounted) {
      final updatedEntry = LocalDbService.entryBox.get(_entry.syncId);
      if (updatedEntry != null && updatedEntry.id != _entry.id) {
        setState(() {
          _entry = updatedEntry;
        });
        _loadItems();
        _loadPayments();
      }
    }
  }

  @override
  void dispose() {
    _itemsListenable.removeListener(_loadItems);
    _paymentsListenable.removeListener(_loadPayments);
    _entryListenable.removeListener(_onEntryChanged);
    super.dispose();
  }

  Future<void> _loadPayments() async {
    setState(() => _loadingPayments = true);

    // Load exclusively from local Hive — SyncManager handles server
    // reconciliation safely with hasPendingOp guards.
    final localList = _entry.syncId != null
        ? LocalDbService.getPaymentsForEntrySyncId(_entry.syncId!)
        : <PartialPayment>[];
    if (mounted) {
      setState(() {
        _payments = localList;
        _loadingPayments = false;
      });
    }
  }

  Future<void> _loadItems() async {
    setState(() => _loadingItems = true);

    // Load exclusively from local Hive — SyncManager handles server
    // reconciliation safely with hasPendingOp guards. Fetching directly
    // from the server here would overwrite pending offline edits (e.g.
    // item releases queued but not yet pushed) with stale server state.
    final localList = _entry.syncId != null
        ? LocalDbService.getItemsForEntrySyncId(_entry.syncId!)
        : LocalDbService.getItemsForEntry(_entry.id ?? -1);
    if (mounted) {
      setState(() {
        _items = localList;
        _loadingItems = false;
      });
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

  String get _itemReleaseStatus {
    if (_items.isEmpty) return 'no_items';
    final statuses = _items.map((i) => i.releaseStatus).toSet();
    if (statuses.every((s) => s == 'released' || s == 'transferred')) return 'all_released';
    if (statuses.contains('held') && statuses.length > 1) return 'partial';
    return 'all_held';
  }

  Color get _releaseStatusColor {
    final status = _itemReleaseStatus;
    if (status == 'all_released') return Colors.blue;
    if (status == 'partial') return Colors.amber.shade700;
    return Colors.green;
  }

  String get _releaseStatusText {
    final status = _itemReleaseStatus;
    if (status == 'all_released') return 'All Items Released';
    if (status == 'partial') return 'Partially Released';
    if (status == 'no_items') return 'No Items';
    return 'All Items Held';
  }

  Future<void> _showReleaseDialog(JewelleryItem item) async {
    final noteCtrl = TextEditingController();
    DateTime? selectedDate = DateTime.now();
    bool confirmed = false;

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('Release ${item.name}'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Mark this item as released? It will no longer be held as collateral.'),
                  const SizedBox(height: 16),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Release Date'),
                    subtitle: Text(selectedDate != null ? DateFormat('yyyy-MM-dd').format(selectedDate!) : 'Select date'),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: selectedDate ?? DateTime.now(),
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (d != null) setDialogState(() => selectedDate = d);
                    },
                  ),
                  TextField(
                    controller: noteCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Note (Optional)',
                      hintText: 'e.g. Returned to customer',
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                ElevatedButton(
                  onPressed: () {
                    confirmed = true;
                    Navigator.pop(ctx);
                  },
                  child: const Text('Release'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed && mounted) {
      await LocalDbService.releaseItem(
        item: item,
        status: 'released',
        date: selectedDate != null ? DateFormat('yyyy-MM-dd').format(selectedDate!) : null,
        note: noteCtrl.text.trim(),
      );
      _loadItems();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${item.name} released successfully')));
    }
  }

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
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: ListView(
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
                      const Spacer(),
                      if (_items.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: _releaseStatusColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: _releaseStatusColor.withOpacity(0.5)),
                          ),
                          child: Text(
                            _releaseStatusText,
                            style: TextStyle(color: _releaseStatusColor, fontWeight: FontWeight.bold, fontSize: 12),
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
                  if (_entry.effectiveTotalPaid > 0) ...[
                    _row('Total Paid', '₹${_entry.effectiveTotalPaid.toStringAsFixed(2)}', highlight: true, valueColor: Colors.green),
                    _row('Remaining Principal', '₹${_entry.effectiveRemainingPrincipal.toStringAsFixed(2)}', highlight: true, valueColor: Colors.orange),
                    _row('Accrued Interest', '₹${_entry.effectiveTotalAccruedInterest.toStringAsFixed(2)}', highlight: true, valueColor: Colors.red),
                  ],
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
                onPressed: _withdrawing ? null : () async {
                  // Double-tap guard
                  if (_withdrawing || !_canWithdraw) return;
                  setState(() => _withdrawing = true);

                  final updated = await Navigator.push<Entry>(
                    context,
                    MaterialPageRoute(builder: (_) => WithdrawScreen(entry: _entry)),
                  );

                  // WithdrawScreen now pops with the fresh Hive entry
                  if (updated != null && mounted) {
                    setState(() {
                      _entry = updated;
                      _withdrawing = false;
                    });
                    // Show receipt immediately after status update
                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => ReceiptScreen(entry: _entry)),
                    );
                  } else if (mounted) {
                    // User cancelled — re-enable button
                    // Also reload from Hive in case Hive was written but entry wasn't returned
                    final syncId = _entry.syncId;
                    if (syncId != null) {
                      final fresh = LocalDbService.entryBox.get(syncId);
                      if (fresh != null && mounted) {
                        setState(() { _entry = fresh; _withdrawing = false; });
                      } else {
                        setState(() => _withdrawing = false);
                      }
                    } else {
                      setState(() => _withdrawing = false);
                    }
                  }
                },
                icon: Icon(Icons.undo, color: _withdrawing ? Colors.grey : Colors.blue),
                label: Text(
                  _withdrawing ? 'Processing…' : 'Withdraw Entry',
                  style: TextStyle(color: _withdrawing ? Colors.grey : Colors.blue),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: _withdrawing ? Colors.grey : Colors.blue),
                ),
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
                title: Row(
                  children: [
                    Expanded(child: Text(item.name, style: const TextStyle(fontWeight: FontWeight.w600))),
                    if (LocalDbService.isQuarantined(item.syncId))
                      const Padding(
                        padding: EdgeInsets.only(left: 8),
                        child: ConflictBadge(),
                      ),
                    if (item.releaseStatus != 'held')
                      Container(
                        margin: const EdgeInsets.only(left: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: item.releaseStatus == 'released' ? Colors.blue.withOpacity(0.1) : Colors.purple.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: item.releaseStatus == 'released' ? Colors.blue : Colors.purple),
                        ),
                        child: Text(
                          item.releaseStatus.toUpperCase(),
                          style: TextStyle(fontSize: 10, color: item.releaseStatus == 'released' ? Colors.blue : Colors.purple, fontWeight: FontWeight.bold),
                        ),
                      )
                  ],
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.itemType),
                    if (item.weight != null) Text('${item.weight} g', style: const TextStyle(fontSize: 12)),
                    if (item.note.isNotEmpty) Text(item.note, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                    if (item.image != null && item.image!.isNotEmpty) 
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: item.image!.startsWith('http') || item.image!.startsWith('/media/')
                              ? Image.network(
                                  item.image!.startsWith('http') 
                                      ? item.image! 
                                      : '${ApiService.baseUrl.replaceAll('/api', '')}${item.image}',
                                  height: 100,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) => const SizedBox(),
                                )
                              : Image.file(
                                  File(item.image!),
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
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (item.releaseStatus == 'held')
                            IconButton(
                              icon: const Icon(Icons.outbox, color: Colors.blue),
                              tooltip: 'Release Item',
                              onPressed: () => _showReleaseDialog(item),
                            ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.red),
                            onPressed: () => _deleteItem(item),
                          ),
                        ],
                      )
                    : null,
              ),
            ))),

          _buildPaymentsSection(),
        ],
        ),
      ),
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

  Widget _row(String label, String value, {bool highlight = false, Color? valueColor}) {
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
              color: valueColor ?? (highlight ? const Color(0xFF5C35D4) : null),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Payments (${_payments.length})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            if (_canEdit)
              TextButton.icon(
                onPressed: () async {
                  final added = await showDialog<bool>(
                    context: context,
                    builder: (_) => PartialPaymentDialog(entry: _entry),
                  );
                  if (added == true) {
                    _loadPayments();
                  }
                },
                icon: const Icon(Icons.add_card, size: 18),
                label: const Text('Add Payment'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (_loadingPayments)
          const Center(child: CircularProgressIndicator())
        else if (_payments.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('No payments recorded yet.', style: TextStyle(color: Colors.grey)),
            ),
          )
        else
          ...(_payments.map((p) => Card(
            child: ListTile(
              leading: const CircleAvatar(
                backgroundColor: Colors.green,
                child: Icon(Icons.currency_rupee, color: Colors.white, size: 18),
              ),
              title: Row(
                children: [
                  Expanded(child: Text('₹${p.amount}', style: const TextStyle(fontWeight: FontWeight.w600))),
                  if (LocalDbService.isQuarantined(p.syncId))
                    const Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: ConflictBadge(),
                    ),
                ],
              ),
              subtitle: Text(
                '${p.date}${p.note.isNotEmpty ? '\n${p.note}' : ''}',
                style: const TextStyle(fontSize: 12),
              ),
              isThreeLine: p.note.isNotEmpty,
            ),
          ))),
      ],
    );
  }
}
