import 'package:hive/hive.dart';

part 'entry.g.dart';

@HiveType(typeId: 2)
class Entry extends HiveObject {
  @HiveField(0)
  int? id;

  @HiveField(1)
  String srNumber;

  @HiveField(2)
  int party;

  @HiveField(3)
  String amount;

  @HiveField(4)
  String interest;

  @HiveField(5)
  String status;

  @HiveField(6)
  String date;

  @HiveField(7)
  double totalPayable;

  @HiveField(8)
  int daysElapsed;

  @HiveField(9)
  String partyName;

  @HiveField(10)
  String note;

  @HiveField(11)
  String? closedAt;

  @HiveField(12)
  String? syncId;

  /// Explicit due date stored as ISO string (yyyy-MM-dd). Nullable — not all
  /// entries have a specific due date set.
  @HiveField(13)
  String? dueDate;

  /// Server-side version counter. Incremented on every PATCH.
  /// Sent with PATCH requests for conflict detection.
  /// Defaults to 1 for old Hive records that predate this field.
  @HiveField(14)
  int version;

  @HiveField(15)
  double? totalPaid;

  @HiveField(16)
  double? remainingPrincipal;

  @HiveField(17)
  double? totalAccruedInterest;

  Entry({
    this.id,
    required this.srNumber,
    required this.party,
    required this.amount,
    required this.interest,
    required this.status,
    required this.date,
    required this.totalPayable,
    required this.daysElapsed,
    required this.partyName,
    this.note = '',
    this.closedAt,
    this.syncId,
    this.dueDate,
    this.version = 1,
    this.totalPaid,
    this.remainingPrincipal,
    this.totalAccruedInterest,
  });

  // ─── Safe non-nullable accessors (backward-compatible) ──────────────────
  /// Total paid so far. Returns 0 for old records that predate this field.
  double get effectiveTotalPaid => totalPaid ?? 0.0;

  /// Remaining principal. Falls back to original amount for old records.
  double get effectiveRemainingPrincipal =>
      remainingPrincipal ?? (double.tryParse(amount) ?? 0.0);

  /// Accrued interest. Returns 0 for old records.
  double get effectiveTotalAccruedInterest => totalAccruedInterest ?? 0.0;

  factory Entry.fromJson(Map<String, dynamic> json) {
    return Entry(
      id:          json['id'],
      srNumber:    json['sr_number'] ?? '',
      party:       json['party'],
      amount:      json['amount'],
      interest:    json['interest'],
      status:      json['status'],
      date:        json['date'],
      totalPayable: (json['total_payable'] as num?)?.toDouble() ?? 0.0,
      daysElapsed: json['days_elapsed'] ?? 0,
      partyName:   json['party_name'] ?? '',
      note:        json['note'] ?? '',
      closedAt:    json['closed_at'],
      syncId:      json['sync_id'],
      dueDate:     json['due_date'],
      version:     (json['version'] as int?) ?? 1,
      totalPaid:   (json['total_paid'] as num?)?.toDouble(),
      remainingPrincipal: (json['remaining_principal'] as num?)?.toDouble()
          ?? (double.tryParse(json['amount'].toString()) ?? 0.0),
      totalAccruedInterest: (json['total_accrued_interest'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'sr_number': srNumber,
      'party':     party,
      'amount':    amount,
      'interest':  interest,
      'status':    status,
      'note':      note,
      if (syncId  != null) 'sync_id':  syncId,
      if (dueDate != null) 'due_date': dueDate,
      'version': version,
    };
  }

  // ─── Computed Properties ───────────────────────────────────────────────

  /// Dynamically compute days elapsed from entry creation date to now.
  /// More accurate than the stored [daysElapsed] which is stale after creation.
  int get computedDaysElapsed {
    final entryDate = DateTime.tryParse(date);
    if (entryDate == null) return daysElapsed;
    if (status == 'WITHDRAWN' || status == 'CLOSED') {
      final closeDate = closedAt != null ? DateTime.tryParse(closedAt!) : null;
      if (closeDate != null) return closeDate.difference(entryDate).inDays;
    }
    return DateTime.now().difference(entryDate).inDays;
  }

  /// Dynamically compute total payable using simple monthly interest.
  /// Mirrors the Django server's total_payable property so the UI shows
  /// an accurate amount even before the entry has ever synced.
  double get computedTotalPayable {
    final principal    = double.tryParse(amount) ?? 0.0;
    final monthlyRate  = double.tryParse(interest) ?? 0.0;
    final days         = computedDaysElapsed;
    final interestAmt  = principal * (monthlyRate / 100) * (days / 30);
    return principal + interestAmt;
  }

  // ─── Due Date Properties ───────────────────────────────────────────────

  /// Parsed due date. Returns null if not set or unparseable.
  DateTime? get parsedDueDate {
    if (dueDate == null || dueDate!.isEmpty) return null;
    return DateTime.tryParse(dueDate!);
  }

  /// True when the entry has an explicit due date configured.
  bool get hasDueDate => parsedDueDate != null;

  /// Human-readable due date string (DD/MM/YYYY). Empty string if not set.
  String get dueDateDisplay {
    final d = parsedDueDate;
    if (d == null) return '';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  /// Days until the due date. Negative means overdue.
  /// Returns null if no due date is set.
  int? get daysUntilDue {
    final d = parsedDueDate;
    if (d == null) return null;
    if (status == 'WITHDRAWN' || status == 'CLOSED') return null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final due   = DateTime(d.year, d.month, d.day);
    return due.difference(today).inDays;
  }

  /// User-friendly label for the remaining days / overdue state.
  String get daysRemainingLabel {
    if (status == 'WITHDRAWN' || status == 'CLOSED') return 'Closed';
    final days = daysUntilDue;
    if (days == null) return '';
    if (days < 0)  return 'Overdue by ${days.abs()} day${days.abs() == 1 ? '' : 's'}';
    if (days == 0) return 'Due today';
    return '$days day${days == 1 ? '' : 's'} remaining';
  }

  /// Color category for the due date label: 'red' | 'orange' | 'green' | 'none'
  String get dueDateSeverity {
    final days = daysUntilDue;
    if (days == null) return 'none';
    if (days < 0)  return 'red';
    if (days <= 3) return 'orange';
    return 'green';
  }

  /// True if this active entry has passed its due date.
  bool get isDueDatePassed {
    final days = daysUntilDue;
    return days != null && days < 0;
  }
}
