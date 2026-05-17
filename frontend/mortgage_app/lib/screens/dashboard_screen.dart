import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/settings_service.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Map<String, dynamic>? _stats;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final stats = await ApiService().fetchStats();
      setState(() { _stats = stats; _loading = false; });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Widget _statCard({
    required String label,
    required String value,
    required Color color,
    required IconData icon,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final businessName = SettingsService.businessName;

    return Scaffold(
      appBar: AppBar(
        title: Text(businessName),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Icon(Icons.wifi_off, size: 60, color: Colors.grey),
                    const SizedBox(height: 12),
                    Text('Connection error', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(_error!, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    const SizedBox(height: 16),
                    ElevatedButton(onPressed: _load, child: const Text('Retry')),
                  ]),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      const SizedBox(height: 8),
                      Text('Overview',
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      GridView.count(
                        crossAxisCount: 2,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                        childAspectRatio: 1.5,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        children: [
                          _statCard(
                            label: 'Total Parties',
                            value: '${_stats!['total_parties']}',
                            color: const Color(0xFF5C35D4),
                            icon: Icons.people,
                          ),
                          _statCard(
                            label: 'Total Entries',
                            value: '${_stats!['total_entries']}',
                            color: Colors.blueGrey,
                            icon: Icons.receipt_long,
                          ),
                          _statCard(
                            label: 'Active',
                            value: '${_stats!['active']}',
                            color: Colors.green[700]!,
                            icon: Icons.check_circle_outline,
                          ),
                          _statCard(
                            label: 'Overdue',
                            value: '${_stats!['overdue']}',
                            color: Colors.orange[700]!,
                            icon: Icons.warning_amber_outlined,
                          ),
                          _statCard(
                            label: 'Withdrawn',
                            value: '${_stats!['withdrawn']}',
                            color: Colors.blue[700]!,
                            icon: Icons.undo,
                          ),
                          _statCard(
                            label: 'Closed',
                            value: '${_stats!['closed']}',
                            color: Colors.grey[600]!,
                            icon: Icons.lock_outline,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text('Amounts',
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      _statCard(
                        label: 'Active Amount',
                        value: '₹${_stats!['active_amount'].toStringAsFixed(0)}',
                        color: Colors.green[700]!,
                        icon: Icons.currency_rupee,
                      ),
                      const SizedBox(height: 8),
                      _statCard(
                        label: 'Overdue Amount',
                        value: '₹${_stats!['overdue_amount'].toStringAsFixed(0)}',
                        color: Colors.orange[700]!,
                        icon: Icons.currency_rupee,
                      ),
                    ],
                  ),
                ),
    );
  }
}
