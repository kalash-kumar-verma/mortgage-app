import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../services/settings_service.dart';
import '../services/local_db_service.dart';
import '../models/party.dart';
import '../models/entry.dart';

class AddEntryScreen extends StatefulWidget {
  final Party party;
  const AddEntryScreen({super.key, required this.party});

  @override
  State<AddEntryScreen> createState() => _AddEntryScreenState();
}

class _AddEntryScreenState extends State<AddEntryScreen> {
  final _amountController   = TextEditingController();
  final _interestController = TextEditingController();
  final _noteController     = TextEditingController();
  DateTime? _selectedDueDate;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    if (widget.party.defaultInterestRate != null) {
      _interestController.text = widget.party.defaultInterestRate.toString();
    } else {
      _interestController.text = SettingsService.defaultInterest;
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _interestController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _pickDueDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDueDate ?? now.add(const Duration(days: 30)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365 * 5)),
      helpText: 'Select Due Date (Optional)',
    );
    if (picked != null) setState(() => _selectedDueDate = picked);
  }

  void _clearDueDate() => setState(() => _selectedDueDate = null);

  String _formatDate(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';

  Future<void> _save() async {
    if (_amountController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Amount is required')));
      return;
    }
    setState(() => _loading = true);
    try {
      int maxSr = 0;
      for (var entry in LocalDbService.entryBox.values) {
        final strVal = entry.srNumber.replaceAll(RegExp(r'[^0-9]'), '');
        final num = int.tryParse(strVal) ?? 0;
        if (num > maxSr) maxSr = num;
      }
      final localSr = 'SR no: ${maxSr + 1}';
      final uniqueNegativeId = -(DateTime.now().millisecondsSinceEpoch % 1000000000);
      final e = Entry(
        id:          uniqueNegativeId,
        syncId:      const Uuid().v4(),
        srNumber:    localSr,
        party:       widget.party.id ?? -1,
        amount:      _amountController.text,
        interest:    _interestController.text.isEmpty ? '0' : _interestController.text,
        status:      'ACTIVE',
        date:        DateTime.now().toIso8601String().split('T')[0],
        totalPayable: double.tryParse(_amountController.text) ?? 0.0,
        daysElapsed: 0,
        partyName:   widget.party.name,
        note:        _noteController.text,
        dueDate:     _selectedDueDate?.toIso8601String().split('T')[0],
      );
      await LocalDbService.saveEntry(e, partySyncId: widget.party.syncId);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('New Entry')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Party chip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(children: [
              Icon(Icons.person, color: scheme.primary, size: 20),
              const SizedBox(width: 10),
              Text(widget.party.name,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: scheme.primary)),
            ]),
          ),
          const SizedBox(height: 20),

          // Amount
          TextField(
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Amount (₹) *',
              prefixIcon: Icon(Icons.currency_rupee),
            ),
          ),
          const SizedBox(height: 16),

          // Interest
          TextField(
            controller: _interestController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Interest Rate (%)',
              prefixIcon: Icon(Icons.percent),
            ),
          ),
          const SizedBox(height: 16),

          // Due date picker
          _buildDueDateTile(scheme),
          const SizedBox(height: 16),

          // Note
          TextField(
            controller: _noteController,
            decoration: const InputDecoration(
              labelText: 'Note (Optional)',
              prefixIcon: Icon(Icons.notes),
            ),
            maxLines: 3,
          ),
          const SizedBox(height: 28),

          ElevatedButton(
            onPressed: _loading ? null : _save,
            style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            child: _loading
                ? const SizedBox(height: 20, width: 20,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Text('Create Entry', style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
  }

  Widget _buildDueDateTile(ColorScheme scheme) {
    return InkWell(
      onTap: _pickDueDate,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(color: scheme.outline),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today_outlined,
                color: _selectedDueDate != null ? scheme.primary : Colors.grey, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Due Date',
                      style: TextStyle(
                          fontSize: 12,
                          color: _selectedDueDate != null ? scheme.primary : Colors.grey[600])),
                  const SizedBox(height: 2),
                  Text(
                    _selectedDueDate != null
                        ? _formatDate(_selectedDueDate!)
                        : 'Optional — tap to set a deadline',
                    style: TextStyle(
                        fontSize: 14,
                        color: _selectedDueDate != null ? scheme.onSurface : Colors.grey[500]),
                  ),
                ],
              ),
            ),
            if (_selectedDueDate != null)
              GestureDetector(
                onTap: _clearDueDate,
                child: Icon(Icons.close, size: 18, color: Colors.grey[600]),
              ),
          ],
        ),
      ),
    );
  }
}
