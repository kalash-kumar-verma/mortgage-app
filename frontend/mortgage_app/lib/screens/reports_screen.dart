import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

import '../services/analytics_service.dart';
import '../services/report_export_service.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../services/local_db_service.dart';
import '../services/pdf_receipt_service.dart';
import '../models/entry.dart';
import '../models/party.dart';
import '../models/jewellery_item.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  String _dateFilter = 'All Time';
  DateTime? _startDate;
  DateTime? _endDate;

  late AnalyticsMetrics _metrics;
  late List<TopCustomer> _topCustomers;

  @override
  void initState() {
    super.initState();
    _calculateMetrics();
  }

  void _calculateMetrics() {
    final now = DateTime.now();
    switch (_dateFilter) {
      case 'Today':
        _startDate = DateTime(now.year, now.month, now.day);
        _endDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
        break;
      case 'This Week':
        _startDate = now.subtract(Duration(days: now.weekday - 1));
        _startDate = DateTime(_startDate!.year, _startDate!.month, _startDate!.day);
        _endDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
        break;
      case 'This Month':
        _startDate = DateTime(now.year, now.month, 1);
        _endDate = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
        break;
      case 'Custom':
        // Custom dates are handled via dialog.
        break;
      default: // All Time
        _startDate = null;
        _endDate = null;
    }

    setState(() {
      _metrics = AnalyticsService.getMetrics(_startDate, _endDate);
      _topCustomers = AnalyticsService.getTopCustomers(); // usually all-time snapshot
    });
  }

  Future<void> _selectCustomDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDateRange: _startDate != null && _endDate != null
          ? DateTimeRange(start: _startDate!, end: _endDate!)
          : null,
    );

    if (picked != null) {
      setState(() {
        _dateFilter = 'Custom';
        _startDate = picked.start;
        _endDate = picked.end;
      });
      _calculateMetrics();
    }
  }

  void _exportCSV() {
    String rangeLabel = _dateFilter;
    if (_dateFilter == 'Custom' && _startDate != null && _endDate != null) {
      rangeLabel = '${DateFormat('MMM d, yyyy').format(_startDate!)} - ${DateFormat('MMM d, yyyy').format(_endDate!)}';
    }
    ReportExportService.exportToCsv(_metrics, _topCustomers, rangeLabel);
  }

  Future<void> _exportAuditRegister(bool asPdf) async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: 'Select Audit Period',
    );

    if (picked == null) return;

    final start = picked.start;
    final end = DateTime(picked.end.year, picked.end.month, picked.end.day, 23, 59, 59);
    final rangeLabel = '${DateFormat('MMM d, yyyy').format(start)} - ${DateFormat('MMM d, yyyy').format(end)}';

    final entryBox = Hive.box<Entry>(LocalDbService.entryBoxName);
    final partyBox = Hive.box<Party>(LocalDbService.partyBoxName);
    final itemBox = Hive.box<JewelleryItem>(LocalDbService.itemBoxName);

    List<Entry> newPledges = [];
    List<Entry> releasedLoans = [];
    Map<int, String> partyNames = {};
    Map<int, String> partyPhones = {};
    Map<int, String> entryItems = {};

    for (var entry in entryBox.values) {
      if (entry.status == 'DELETED') continue;

      // Check New Pledges
      final eDate = DateTime.tryParse(entry.date);
      if (eDate != null && eDate.isAfter(start) && eDate.isBefore(end)) {
        newPledges.add(entry);
      }

      // Check Released
      if ((entry.status == 'WITHDRAWN' || entry.status == 'CLOSED') && entry.closedAt != null) {
        final cDate = DateTime.tryParse(entry.closedAt!);
        if (cDate != null && cDate.isAfter(start) && cDate.isBefore(end)) {
          releasedLoans.add(entry);
        }
      }

      // Pre-fetch names
      if (!partyNames.containsKey(entry.party)) {
        final p = partyBox.get(entry.party);
        if (p != null) {
          partyNames[p.id!] = p.name;
          partyPhones[p.id!] = p.phone;
        }
      }

      // Pre-fetch items
      if (!entryItems.containsKey(entry.id)) {
        final items = itemBox.values.where((i) => i.entry == entry.id).toList();
        final desc = items.map((i) => '${i.name} (${i.weight ?? '-'}g)').join(', ');
        entryItems[entry.id!] = desc;
      }
    }

    newPledges.sort((a, b) => a.date.compareTo(b.date));
    releasedLoans.sort((a, b) => (a.closedAt ?? '').compareTo(b.closedAt ?? ''));

    if (asPdf) {
      await PdfReceiptService.shareAuditRegisterPdf(rangeLabel, newPledges, releasedLoans, partyNames, partyPhones, entryItems);
    } else {
      await ReportExportService.exportAuditRegisterCsv(rangeLabel, newPledges, releasedLoans, partyNames, partyPhones, entryItems);
    }
  }

  Widget _buildSummaryCard(String title, String value, IconData icon, Color color) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  Icon(icon, size: 18, color: color),
                  const SizedBox(width: 8),
                  Text(title, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                ],
              ),
              const SizedBox(height: 8),
              Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChart() {
    return AspectRatio(
      aspectRatio: 1.5,
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.grey.shade200),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Portfolio Distribution', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 24),
              Expanded(
                child: BarChart(
                  BarChartData(
                    alignment: BarChartAlignment.spaceAround,
                    maxY: (_metrics.activePrincipal + _metrics.overdueAmount + _metrics.withdrawnAmount) * 1.2,
                    barTouchData: BarTouchData(enabled: false),
                    titlesData: FlTitlesData(
                      show: true,
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (value, meta) {
                            switch (value.toInt()) {
                              case 0: return const Text('Active', style: TextStyle(fontSize: 10));
                              case 1: return const Text('Overdue', style: TextStyle(fontSize: 10));
                              case 2: return const Text('Withdrawn\n(Period)', style: TextStyle(fontSize: 10, height: 1.1), textAlign: TextAlign.center);
                              default: return const Text('');
                            }
                          },
                        ),
                      ),
                      leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    ),
                    gridData: const FlGridData(show: false),
                    borderData: FlBorderData(show: false),
                    barGroups: [
                      BarChartGroupData(
                        x: 0,
                        barRods: [BarChartRodData(toY: _metrics.activePrincipal, color: Colors.blue, width: 20, borderRadius: BorderRadius.circular(4))],
                      ),
                      BarChartGroupData(
                        x: 1,
                        barRods: [BarChartRodData(toY: _metrics.overdueAmount, color: Colors.orange, width: 20, borderRadius: BorderRadius.circular(4))],
                      ),
                      BarChartGroupData(
                        x: 2,
                        barRods: [BarChartRodData(toY: _metrics.withdrawnAmount, color: Colors.teal, width: 20, borderRadius: BorderRadius.circular(4))],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopCustomers() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Top Customers', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (_topCustomers.isEmpty)
              const Text('No data available.', style: TextStyle(color: Colors.grey)),
            for (var tc in _topCustomers)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(backgroundColor: Colors.blue.shade50, child: const Icon(Icons.person, color: Colors.blue)),
                title: Text(tc.party.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('${tc.transactions} Active Tx', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                trailing: Text('₹${tc.activeAmount.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAuditRegister() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.blue.shade200, width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.assignment_turned_in, color: Colors.blue.shade700),
                const SizedBox(width: 8),
                const Text('Audit Register (Khatabook)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            const SizedBox(height: 8),
            Text('Chronological ledger of all new pledges and released loans for compliance and audit.', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _exportAuditRegister(false),
                    icon: const Icon(Icons.table_chart),
                    label: const Text('Export CSV'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _exportAuditRegister(true),
                    icon: const Icon(Icons.picture_as_pdf),
                    label: const Text('Export PDF'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade700, foregroundColor: Colors.white),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports & Analytics'),
        actions: [
          IconButton(
            icon: const Icon(Icons.ios_share),
            onPressed: _exportCSV,
            tooltip: 'Export CSV',
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  const Text('Filter:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                  const SizedBox(width: 8),
                  DropdownButton<String>(
                    value: _dateFilter,
                    underline: const SizedBox(),
                    items: ['All Time', 'Today', 'This Week', 'This Month', 'Custom']
                        .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                        .toList(),
                    onChanged: (val) {
                      if (val == 'Custom') {
                        _selectCustomDateRange();
                      } else if (val != null) {
                        setState(() => _dateFilter = val);
                        _calculateMetrics();
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            sliver: SliverGrid.count(
              crossAxisCount: 2,
              childAspectRatio: 1.5,
              children: [
                _buildSummaryCard('Active Principal', '₹${_metrics.activePrincipal.toStringAsFixed(0)}', Icons.account_balance_wallet, Colors.blue),
                _buildSummaryCard('Expected Interest', '₹${_metrics.expectedInterest.toStringAsFixed(0)}', Icons.trending_up, Colors.green),
                _buildSummaryCard('Overdue Amount', '₹${_metrics.overdueAmount.toStringAsFixed(0)}', Icons.warning_amber, Colors.orange),
                _buildSummaryCard('Collection (Period)', '₹${_metrics.paymentsReceived.toStringAsFixed(0)}', Icons.payments, Colors.teal),
              ],
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _buildChart(),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: _buildTopCustomers(),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: _buildAuditRegister(),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }
}
