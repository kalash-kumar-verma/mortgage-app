import 'package:flutter/material.dart';
import '../models/entry.dart';
import '../services/local_db_service.dart';

class EditEntryScreen extends StatefulWidget {
  final Entry entry;
  const EditEntryScreen({super.key, required this.entry});

  @override
  State<EditEntryScreen> createState() => _EditEntryScreenState();
}

class _EditEntryScreenState extends State<EditEntryScreen> {
  late TextEditingController _amountController;
  late TextEditingController _interestController;
  late TextEditingController _noteController;
  DateTime? _selectedDueDate;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _amountController   = TextEditingController(text: widget.entry.amount);
    _interestController = TextEditingController(text: widget.entry.interest);
    _noteController     = TextEditingController(text: widget.entry.note);
    // Pre-populate existing due date
    if (widget.entry.dueDate != null && widget.entry.dueDate!.isNotEmpty) {
      _selectedDueDate = DateTime.tryParse(widget.entry.dueDate!);
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
      firstDate: DateTime(2020),
      lastDate: now.add(const Duration(days: 365 * 5)),
      helpText: 'Select Due Date (Optional)',
    );
    if (picked != null) setState(() => _selectedDueDate = picked);
  }

  void _clearDueDate() => setState(() => _selectedDueDate = null);

  String _formatDate(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';

  Future<void> _save() async {
    setState(() => _loading = true);
    try {
      final updated = Entry(
        id:           widget.entry.id,
        syncId:       widget.entry.syncId,
        srNumber:     widget.entry.srNumber,
        party:        widget.entry.party,
        partyName:    widget.entry.partyName,
        amount:       _amountController.text,
        interest:     _interestController.text.isEmpty ? '0' : _interestController.text,
        status:       widget.entry.status,
        totalPayable: widget.entry.totalPayable,
        daysElapsed:  widget.entry.daysElapsed,
        date:         widget.entry.date,
        note:         _noteController.text,
        closedAt:     widget.entry.closedAt,
        dueDate:      _selectedDueDate?.toIso8601String().split('T')[0],
        version:      widget.entry.version,
      );
      await LocalDbService.saveEntry(updated);
      if (mounted) Navigator.pop(context, updated);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isPending = widget.entry.id == null || widget.entry.id! < 0;
    return Scaffold(
      appBar: AppBar(
        title: Text('Edit ${isPending ? 'Pending Entry' : widget.entry.srNumber}'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Amount (₹)',
              prefixIcon: Icon(Icons.currency_rupee),
            ),
          ),
          const SizedBox(height: 16),
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
                : const Text('Save Changes', style: TextStyle(fontSize: 16)),
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
              )
            else
              Icon(Icons.arrow_drop_down, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }
}
