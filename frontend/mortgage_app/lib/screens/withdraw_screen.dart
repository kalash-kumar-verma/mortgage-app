import 'package:flutter/material.dart';
import '../models/entry.dart';
import '../services/settings_service.dart';
import '../services/local_db_service.dart';
import '../services/sync_manager.dart';

class WithdrawScreen extends StatefulWidget {
  final Entry entry;
  const WithdrawScreen({super.key, required this.entry});

  @override
  State<WithdrawScreen> createState() => _WithdrawScreenState();
}

class _WithdrawScreenState extends State<WithdrawScreen> {
  final _pinController = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  /// Compute total payable locally: principal + simple monthly interest.
  /// Mirrors the Django server's total_payable @property — accurate offline.
  double get _computedTotalPayable {
    final principal = double.tryParse(widget.entry.amount) ?? 0.0;
    final monthlyRate = double.tryParse(widget.entry.interest) ?? 0.0;
    final entryDate = DateTime.tryParse(widget.entry.date) ?? DateTime.now();
    final daysElapsed = DateTime.now().difference(entryDate).inDays;
    // Simple interest: Principal × Rate/100 × (days / 30)
    final interest = principal * (monthlyRate / 100) * (daysElapsed / 30);
    return principal + interest;
  }

  Future<void> _withdraw() async {
    final pin = SettingsService.withdrawPin;
    if (_pinController.text != pin) {
      setState(() => _error = 'Incorrect PIN');
      return;
    }

    // Guard: already withdrawn — should never reach here, but be safe
    if (widget.entry.status == 'WITHDRAWN') {
      if (mounted) Navigator.pop(context, widget.entry);
      return;
    }

    setState(() { _loading = true; _error = null; });

    try {
      await LocalDbService.withdrawEntry(widget.entry);

      // Trigger background sync — non-blocking (fire-and-forget)
      SyncManager().performFullSync();

      // Reload the fresh entry from Hive so the caller gets accurate state
      final syncId = widget.entry.syncId;
      final freshEntry = syncId != null
          ? LocalDbService.entryBox.get(syncId) ?? widget.entry
          : widget.entry;

      if (mounted) {
        // Pop back to EntryDetailScreen WITH the updated entry
        Navigator.pop(context, freshEntry);
      }
    } catch (e) {
      if (mounted) {
        setState(() { _loading = false; _error = e.toString(); });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalPayable = _computedTotalPayable;
    final principal = double.tryParse(widget.entry.amount) ?? 0.0;
    final interestAmount = totalPayable - principal;

    return Scaffold(
      appBar: AppBar(title: Text('Withdraw ${widget.entry.srNumber}')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              color: Colors.blue[50],
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    const Text('Total Amount to Collect', style: TextStyle(fontSize: 16, color: Colors.blueGrey)),
                    const SizedBox(height: 8),
                    Text(
                      '₹${totalPayable.toStringAsFixed(2)}',
                      style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.blue),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Principal: ₹${principal.toStringAsFixed(2)}  |  Interest: ₹${interestAmount.toStringAsFixed(2)}',
                      style: TextStyle(fontSize: 12, color: Colors.blueGrey[400]),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),
            const Text('Enter Security PIN to confirm withdrawal', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            TextField(
              controller: _pinController,
              keyboardType: TextInputType.number,
              obscureText: true,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 24, letterSpacing: 8),
              maxLength: 4,
              decoration: InputDecoration(
                hintText: '****',
                errorText: _error,
                counterText: '',
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _loading ? null : _withdraw,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _loading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('Confirm Withdrawal', style: TextStyle(fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }
}
