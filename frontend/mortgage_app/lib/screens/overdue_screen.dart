import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/local_db_service.dart';
import '../models/entry.dart';
import '../models/party.dart';

class OverdueScreen extends StatefulWidget {
  const OverdueScreen({super.key});

  @override
  State<OverdueScreen> createState() => _OverdueScreenState();
}

class _OverdueScreenState extends State<OverdueScreen> {
  late Box<Entry> _entryBox;
  late Box<Party> _partyBox;
  List<Entry> _overdueEntries = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initBoxes();
  }

  void _initBoxes() {
    _entryBox = Hive.box<Entry>(LocalDbService.entryBoxName);
    _partyBox = Hive.box<Party>(LocalDbService.partyBoxName);
    _loadOverdueEntries();
  }

  void _loadOverdueEntries() {
    final List<Entry> overdue = [];
    for (var entry in _entryBox.values) {
      if (entry.status == 'ACTIVE') {
        if (entry.isDueDatePassed) {
          overdue.add(entry);
        } else if (entry.status == 'OVERDUE') {
          // Fallback if backend marks it overdue
          overdue.add(entry);
        }
      } else if (entry.status == 'OVERDUE') {
        overdue.add(entry);
      }
    }

    // Sort by most overdue first (lowest daysUntilDue)
    overdue.sort((a, b) {
      final aDue = a.daysUntilDue ?? 0;
      final bDue = b.daysUntilDue ?? 0;
      return aDue.compareTo(bDue);
    });

    setState(() {
      _overdueEntries = overdue;
      _isLoading = false;
    });
  }

  Future<void> _makePhoneCall(String phone) async {
    final cleanPhone = phone.replaceAll(RegExp(r'[^\d+]'), '');
    if (cleanPhone.isEmpty) {
      _showError('No valid phone number found');
      return;
    }

    final Uri launchUri = Uri(
      scheme: 'tel',
      path: cleanPhone,
    );
    try {
      if (await canLaunchUrl(launchUri)) {
        await launchUrl(launchUri);
      } else {
        _showError('Could not launch dialer');
      }
    } catch (e) {
      _showError('Could not launch dialer');
    }
  }

  Future<void> _sendWhatsApp(String phone, String message) async {
    final cleanPhone = phone.replaceAll(RegExp(r'[^\d+]'), '');
    if (cleanPhone.isEmpty) {
      _showError('No valid phone number found');
      return;
    }

    final Uri launchUri = Uri.parse(
        'https://wa.me/$cleanPhone?text=${Uri.encodeComponent(message)}');
    try {
      if (await canLaunchUrl(launchUri)) {
        await launchUrl(launchUri, mode: LaunchMode.externalApplication);
      } else {
        _showError('Could not launch WhatsApp');
      }
    } catch (e) {
      _showError('Could not launch WhatsApp');
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Overdue Recovery Desk'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _overdueEntries.isEmpty
              ? const Center(child: Text('No overdue loans!'))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _overdueEntries.length,
                  itemBuilder: (context, index) {
                    final entry = _overdueEntries[index];
                    final party = _partyBox.get(entry.party);
                    final name = party?.name ?? entry.partyName;
                    final phone = party?.phone ?? '';

                    final daysOverdue = (entry.daysUntilDue ?? 0).abs();
                    final totalPayable = entry.computedTotalPayable;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.red.shade200),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    name,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.red.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '$daysOverdue Days Overdue',
                                    style: TextStyle(
                                      color: Colors.red.shade700,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text('SR Number: ${entry.srNumber}', style: TextStyle(color: Colors.grey.shade600)),
                            Text('Phone: $phone', style: TextStyle(color: Colors.grey.shade600)),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Total Payable', style: TextStyle(fontSize: 12, color: Colors.grey)),
                                    Text('₹${totalPayable.toStringAsFixed(0)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red)),
                                  ],
                                ),
                              ],
                            ),
                            const Divider(height: 24),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: phone.isEmpty ? null : () => _makePhoneCall(phone),
                                    icon: const Icon(Icons.phone),
                                    label: const Text('Call'),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: phone.isEmpty
                                        ? null
                                        : () {
                                            final msg = 'Hello $name, your jewellery pledge ${entry.srNumber} is overdue by $daysOverdue days. Please settle the outstanding amount of Rs. ${totalPayable.toStringAsFixed(0)} to avoid penalties.';
                                            _sendWhatsApp(phone, msg);
                                          },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.green.shade600,
                                      foregroundColor: Colors.white,
                                    ),
                                    icon: const Icon(Icons.message),
                                    label: const Text('WhatsApp'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
