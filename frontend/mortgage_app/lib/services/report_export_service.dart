import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';

import 'analytics_service.dart';
import '../models/entry.dart';
import '../services/settings_service.dart';

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

  static Future<void> exportAuditRegisterCsv(
      String rangeLabel,
      List<Entry> newPledges,
      List<Entry> releasedLoans,
      Map<int, String> partyNames,
      Map<int, String> partyPhones,
      Map<int, String> entryItems) async {
    List<List<dynamic>> rows = [];

    // Header
    rows.add(['Audit Register (Khatabook)']);
    rows.add(['Business Name:', SettingsService.businessName]);
    rows.add(['Period:', rangeLabel]);
    rows.add(['Generated On:', DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())]);
    rows.add([]);

    // Section 1
    rows.add(['--- SECTION 1: NEW PLEDGES (CASH OUT) ---']);
    rows.add(['Pledge Date', 'SR No.', 'Customer Name', 'Phone', 'Items', 'Principal (Rs)', 'Status']);
    if (newPledges.isEmpty) {
      rows.add(['No records found for this period.']);
    } else {
      for (var e in newPledges) {
        final name = partyNames[e.party] ?? e.partyName;
        final phone = partyPhones[e.party] ?? '';
        final items = entryItems[e.id ?? 0] ?? '';
        rows.add([e.date, e.srNumber, name, phone, items, e.amount, e.status]);
      }
    }
    rows.add([]);

    // Section 2
    rows.add(['--- SECTION 2: RELEASED LOANS (CASH IN) ---']);
    rows.add(['Release Date', 'SR No.', 'Customer Name', 'Phone', 'Items', 'Principal + Interest', 'Status']);
    if (releasedLoans.isEmpty) {
      rows.add(['No records found for this period.']);
    } else {
      for (var e in releasedLoans) {
        final name = partyNames[e.party] ?? e.partyName;
        final phone = partyPhones[e.party] ?? '';
        final items = entryItems[e.id ?? 0] ?? '';
        final dateCol = e.closedAt ?? e.date;
        final amountCol = '${e.amount} + ${e.effectiveTotalPaid - (double.tryParse(e.amount) ?? 0)}';
        rows.add([dateCol, e.srNumber, name, phone, items, amountCol, e.status]);
      }
    }

    String csv = rows.map((row) => row.join(',')).join('\n');

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/audit_register_${DateTime.now().millisecondsSinceEpoch}.csv');
    await file.writeAsString(csv);

    await Share.shareXFiles([XFile(file.path)], text: 'Audit Register Report');
  }
}
