import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';
import '../models/entry.dart';
import '../models/sync_action.dart';
import '../services/api_service.dart';
import '../services/settings_service.dart';
import '../services/local_db_service.dart';
import 'receipt_screen.dart';

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

  Future<void> _withdraw() async {
    final pin = SettingsService.withdrawPin;
    if (_pinController.text != pin) {
      setState(() => _error = 'Incorrect PIN');
      return;
    }

    setState(() { _loading = true; _error = null; });
    if (widget.entry.id == null) {
      setState(() { _loading = false; _error = 'Entry is not synced yet.'; });
      return;
    }
    try {
      // Offline-first approach: Instantly update locally and queue the action.
      // SyncManager will handle the server communication in the background.
      await LocalDbService.withdrawEntry(widget.entry);

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => ReceiptScreen(entry: widget.entry)),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() { _loading = false; _error = e.toString(); });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
                      '₹${widget.entry.totalPayable.toStringAsFixed(2)}',
                      style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.blue),
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
