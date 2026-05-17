import 'package:flutter/material.dart';
import '../models/entry.dart';
import '../services/api_service.dart';

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
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(text: widget.entry.amount);
    _interestController = TextEditingController(text: widget.entry.interest);
    _noteController = TextEditingController(text: widget.entry.note);
  }

  @override
  void dispose() {
    _amountController.dispose();
    _interestController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (widget.entry.id == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Entry not synced yet.')));
      return;
    }
    setState(() => _loading = true);
    try {
      await ApiService().updateEntry(
        widget.entry.id!,
        amount: _amountController.text,
        interest: _interestController.text,
        note: _noteController.text,
      );
      
      // Construct updated entry to return
      final updated = Entry(
        id: widget.entry.id,
        syncId: widget.entry.syncId,
        srNumber: widget.entry.srNumber,
        party: widget.entry.party,
        partyName: widget.entry.partyName,
        amount: _amountController.text,
        interest: _interestController.text,
        status: widget.entry.status,
        totalPayable: widget.entry.totalPayable, // approximate until refresh
        daysElapsed: widget.entry.daysElapsed,
        date: widget.entry.date,
        note: _noteController.text,
        closedAt: widget.entry.closedAt,
      );

      if (mounted) Navigator.pop(context, updated);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Edit ${widget.entry.srNumber}')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            TextField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Amount (₹)'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _interestController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Interest Rate (%)'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _noteController,
              decoration: const InputDecoration(labelText: 'Note (Optional)'),
              maxLines: 3,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loading ? null : _save,
              child: _loading ? const CircularProgressIndicator(color: Colors.white) : const Text('Save Changes'),
            ),
          ],
        ),
      ),
    );
  }
}
