import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';

import 'analytics_service.dart';

class ReportExportService {
  
  static Future<void> exportToCsv(AnalyticsMetrics metrics, List<TopCustomer> topCustomers, String dateRangeLabel) async {
    List<List<dynamic>> rows = [];

    // Header
    rows.add(['Jewellery Mortgage Report']);
    rows.add(['Date Range:', dateRangeLabel]);
    rows.add(['Generated On:', DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())]);
    rows.add([]);

    // Metrics
    rows.add(['--- OVERVIEW METRICS ---']);
    rows.add(['Metric', 'Value']);
    rows.add(['Total Active Principal', metrics.activePrincipal.toStringAsFixed(2)]);
    rows.add(['Total Expected Interest', metrics.expectedInterest.toStringAsFixed(2)]);
    rows.add(['Total Overdue Amount', metrics.overdueAmount.toStringAsFixed(2)]);
    rows.add(['Total Withdrawn Amount', metrics.withdrawnAmount.toStringAsFixed(2)]);
    rows.add(['Partial Payments Received', metrics.paymentsReceived.toStringAsFixed(2)]);
    rows.add(['Total Active Entries', metrics.activeEntries]);
    rows.add([]);

    // Top Customers
    rows.add(['--- TOP CUSTOMERS ---']);
    rows.add(['Party Name', 'Active Amount', 'Transactions']);
    for (var tc in topCustomers) {
      rows.add([tc.party.name, tc.activeAmount.toStringAsFixed(2), tc.transactions]);
    }

    String csv = rows.map((row) => row.join(',')).join('\n');

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/mortgage_report_${DateTime.now().millisecondsSinceEpoch}.csv');
    await file.writeAsString(csv);

    await Share.shareXFiles([XFile(file.path)], text: 'Mortgage Analytics Report');
  }
}
