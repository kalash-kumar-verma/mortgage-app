import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../services/api_service.dart';
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
  final _amountController = TextEditingController();
  final _interestController = TextEditingController();
  final _noteController = TextEditingController();
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    // Auto-fill interest rate: Party custom rate -> Global default
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

  Future<void> _save() async {
    if (_amountController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Amount is required')));
      return;
    }

    setState(() => _loading = true);

    try {
      // Calculate the next sequential SR number based on existing local entries
      int maxSr = 0;
      for (var entry in LocalDbService.entryBox.values) {
        // Extract digits in case there's a prefix, but user wants plain numbers like 1, 2, 3
        final strVal = entry.srNumber.replaceAll(RegExp(r'[^0-9]'), '');
        final num = int.tryParse(strVal) ?? 0;
        if (num > maxSr) maxSr = num;
      }
      final localSr = 'SR no: ${maxSr + 1}';
      final uniqueNegativeId = -(DateTime.now().millisecondsSinceEpoch % 1000000000);
      final e = Entry(
        id: uniqueNegativeId,
        syncId: const Uuid().v4(),
        srNumber: localSr,
        party: widget.party.id ?? -1,
        amount: _amountController.text,
        interest: _interestController.text.isEmpty ? '0' : _interestController.text,
        status: 'ACTIVE',
        date: DateTime.now().toIso8601String().split('T')[0],
        totalPayable: double.tryParse(_amountController.text) ?? 0.0,
        daysElapsed: 0,
        partyName: widget.party.name,
        note: _noteController.text,
      );
      
      // Instantly save to local database (this will also queue the sync operation)
      // Pass the party's syncId so SyncManager can resolve the parent if it's also pending.
      await LocalDbService.saveEntry(e, partySyncId: widget.party.syncId);
      
      if (mounted) Navigator.pop(context, true);

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New Entry')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF5C35D4).withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.person, color: Color(0xFF5C35D4)),
                  const SizedBox(width: 8),
                  Text(widget.party.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Amount (₹) *', prefixIcon: Icon(Icons.currency_rupee)),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _interestController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Interest Rate (%)', prefixIcon: Icon(Icons.percent)),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _noteController,
              decoration: const InputDecoration(labelText: 'Note (Optional)', prefixIcon: Icon(Icons.notes)),
              maxLines: 3,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loading ? null : _save,
              child: _loading 
                  ? const CircularProgressIndicator(color: Colors.white) 
                  : const Text('Create Entry'),
            ),
          ],
        ),
      ),
    );
  }
}
