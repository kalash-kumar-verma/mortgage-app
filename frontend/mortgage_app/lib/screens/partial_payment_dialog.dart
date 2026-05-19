import 'package:flutter/material.dart';
import '../models/entry.dart';
import '../models/partial_payment.dart';
import '../services/local_db_service.dart';
import 'package:uuid/uuid.dart';

class PartialPaymentDialog extends StatefulWidget {
  final Entry entry;

  const PartialPaymentDialog({super.key, required this.entry});

  @override
  State<PartialPaymentDialog> createState() => _PartialPaymentDialogState();
}

class _PartialPaymentDialogState extends State<PartialPaymentDialog> {
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  bool _saving = false;
  
  late double _remainingPrincipal;
  late double _unpaidInterest;
  late double _totalPayable;

  @override
  void initState() {
    super.initState();
    _remainingPrincipal = widget.entry.effectiveRemainingPrincipal > 0
        ? widget.entry.effectiveRemainingPrincipal
        : double.tryParse(widget.entry.amount) ?? 0.0;
    _unpaidInterest = widget.entry.effectiveTotalAccruedInterest;
    _totalPayable = widget.entry.computedTotalPayable;
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _savePayment() async {
    final amtStr = _amountController.text.trim();
    if (amtStr.isEmpty) return;

    final amt = double.tryParse(amtStr);
    if (amt == null || amt <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid positive amount')));
      return;
    }

    if (amt > _totalPayable) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Payment exceeds total payable amount!')));
      return;
    }

    setState(() => _saving = true);

    try {
      final payment = PartialPayment(
        entry: widget.entry.id ?? -1,
        amount: amt.toStringAsFixed(2),
        date: DateTime.now().toIso8601String(),
        note: _noteController.text.trim(),
        syncId: const Uuid().v4(),
      );

      await LocalDbService.savePayment(
        payment, 
        entrySyncId: widget.entry.id != null && widget.entry.id! > 0 ? null : widget.entry.syncId
      );

      // We do not immediately mutate the entry's totals because we rely on the server 
      // or the pull sync to refresh the accurate mathematical state to prevent local desyncs.
      // However, we can trigger a sync if needed.

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Partial Payment'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Remaining Principal: ₹${_remainingPrincipal.toStringAsFixed(2)}', style: const TextStyle(fontSize: 13)),
                  const SizedBox(height: 4),
                  Text('Unpaid Interest: ₹${_unpaidInterest.toStringAsFixed(2)}', style: const TextStyle(fontSize: 13)),
                  const Divider(),
                  Text('Total Owed: ₹${_totalPayable.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Payment Amount (₹)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.currency_rupee),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _noteController,
              decoration: const InputDecoration(
                labelText: 'Note (Optional)',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _savePayment,
          child: _saving 
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : const Text('Save Payment'),
        ),
      ],
    );
  }
}
