import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../models/party.dart';
import '../services/local_db_service.dart';
import '../services/api_service.dart';

class AddPartyScreen extends StatefulWidget {
  const AddPartyScreen({super.key});

  @override
  State<AddPartyScreen> createState() => _AddPartyScreenState();
}

class _AddPartyScreenState extends State<AddPartyScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _noteController = TextEditingController();
  final _interestController = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _noteController.dispose();
    _interestController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Name is required')));
      return;
    }

    setState(() => _loading = true);

    final connectivity = await Connectivity().checkConnectivity();
    final isOnline = !connectivity.contains(ConnectivityResult.none);

    try {
      if (isOnline) {
        // ── Online: Create via API to get a real ID immediately ──
        final response = await ApiService().createPartyAndReturn(
          name: _nameController.text,
          phone: _phoneController.text,
          address: _addressController.text,
          note: _noteController.text,
          defaultInterestRate: _interestController.text.isNotEmpty ? _interestController.text : null,
        );
        response.syncId = 'server-${response.id}';
        await LocalDbService.saveParty(response, isSync: true);
      } else {
        // ── Offline: Save locally as pending ──
        final p = Party(
          syncId: const Uuid().v4(),
          name: _nameController.text,
          phone: _phoneController.text,
          address: _addressController.text,
          note: _noteController.text,
          defaultInterestRate: _interestController.text.isNotEmpty ? double.tryParse(_interestController.text) : null,
        );
        await LocalDbService.saveParty(p);
      }

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Party')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Name *', prefixIcon: Icon(Icons.person)),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone', prefixIcon: Icon(Icons.phone)),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _addressController,
              decoration: const InputDecoration(labelText: 'Address', prefixIcon: Icon(Icons.location_on)),
              maxLines: 2,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _noteController,
              decoration: const InputDecoration(labelText: 'Note (Optional)', prefixIcon: Icon(Icons.notes)),
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _interestController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Default Custom Interest Rate (%)',
                prefixIcon: Icon(Icons.percent),
                helperText: 'Leave blank to use global default',
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loading ? null : _save,
              child: _loading ? const CircularProgressIndicator(color: Colors.white) : const Text('Save Party'),
            ),
          ],
        ),
      ),
    );
  }
}
