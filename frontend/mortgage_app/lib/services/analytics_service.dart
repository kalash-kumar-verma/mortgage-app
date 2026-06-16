import '../models/party.dart';
import 'local_db_service.dart';

class AnalyticsMetrics {
  final double activePrincipal;
  final double expectedInterest;
  final double overdueAmount;
  final double withdrawnAmount;
  final double paymentsReceived; // collection in period
  final int activeEntries;

  AnalyticsMetrics({
    required this.activePrincipal,
    required this.expectedInterest,
    required this.overdueAmount,
    required this.withdrawnAmount,
    required this.paymentsReceived,
    required this.activeEntries,
  });
}

class TopCustomer {
  final Party party;
  final double activeAmount;
  final int transactions;

  TopCustomer({
    required this.party,
    required this.activeAmount,
    required this.transactions,
  });
}

class AnalyticsService {
  
  static AnalyticsMetrics getMetrics(DateTime? start, DateTime? end) {
    double activePrincipal = 0.0;
    double expectedInterest = 0.0;
    double overdueAmount = 0.0;
    double withdrawnAmount = 0.0;
    double paymentsReceived = 0.0;
    int activeEntries = 0;

    // 1. Process Entries
    for (final entry in LocalDbService.entryBox.values) {
      if (entry.status == 'DELETED') continue;
      
      final isOverdue = entry.status == 'OVERDUE' || entry.isDueDatePassed;
      final isActive = entry.status == 'ACTIVE' || isOverdue;
      final isWithdrawn = entry.status == 'WITHDRAWN' || entry.status == 'CLOSED';

      if (isActive) {
        activeEntries++;
        activePrincipal += entry.effectiveRemainingPrincipal;
        expectedInterest += entry.effectiveTotalAccruedInterest;
        if (isOverdue) {
          overdueAmount += entry.computedTotalPayable;
        }
      }

      if (isWithdrawn && entry.closedAt != null) {
        final closedDate = DateTime.tryParse(entry.closedAt!);
        if (closedDate != null && _isInRange(closedDate, start, end)) {
          withdrawnAmount += entry.computedTotalPayable;
        }
      }
    }

    // 2. Process Payments
    for (final payment in LocalDbService.paymentBox.values) {
      final dt = DateTime.tryParse(payment.date) ?? DateTime.now(); 
      if (_isInRange(dt, start, end)) {
        paymentsReceived += double.tryParse(payment.amount) ?? 0.0;
      }
    }

    return AnalyticsMetrics(
      activePrincipal: activePrincipal,
      expectedInterest: expectedInterest,
      overdueAmount: overdueAmount,
      withdrawnAmount: withdrawnAmount,
      paymentsReceived: paymentsReceived,
      activeEntries: activeEntries,
    );
  }

  static List<TopCustomer> getTopCustomers() {
    final Map<int, TopCustomer> customerMap = {};

    for (final party in LocalDbService.partyBox.values) {
      if (party.id == null) continue; // Skip strictly unsynced if needed, or handle by syncId
      customerMap[party.id!] = TopCustomer(party: party, activeAmount: 0.0, transactions: 0);
    }

    for (final entry in LocalDbService.entryBox.values) {
      if (entry.status == 'DELETED') continue;
      
      final partyId = entry.party;
      if (!customerMap.containsKey(partyId)) continue;
      
      final isActive = entry.status == 'ACTIVE' || entry.status == 'OVERDUE' || entry.isDueDatePassed;
      
      final existing = customerMap[partyId]!;
      customerMap[partyId] = TopCustomer(
        party: existing.party,
        activeAmount: existing.activeAmount + (isActive ? entry.effectiveRemainingPrincipal : 0.0),
        transactions: existing.transactions + 1,
      );
    }

    final list = customerMap.values.toList();
    list.sort((a, b) => b.activeAmount.compareTo(a.activeAmount)); // Descending by amount
    return list.take(5).toList();
  }

  static bool _isInRange(DateTime date, DateTime? start, DateTime? end) {
    if (start != null && date.isBefore(start)) return false;
    if (end != null && date.isAfter(end)) return false;
    return true;
  }
}
