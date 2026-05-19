import 'dart:async';
import 'package:flutter/material.dart';
import '../services/settings_service.dart';
import '../services/local_db_service.dart';
import '../services/sync_manager.dart';
import '../models/entry.dart';
import 'entry_detail_screen.dart';
import 'sync_diagnostics_screen.dart';
import 'filtered_entry_list_screen.dart';
import 'party_screen.dart';
import 'reports_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Map<String, dynamic>? _stats;
  List<Entry> _recentEntries = [];
  bool _loading = true;
  StreamSubscription? _entrySub;
  StreamSubscription? _partySub;

  @override
  void initState() {
    super.initState();
    _load();
    SyncManager().isSyncingNotifier.addListener(_onSyncStatusChanged);
    // Live refresh when local Hive boxes change (after create/edit/delete)
    _entrySub = LocalDbService.entryBox.watch().listen((_) => _loadSilently());
    _partySub = LocalDbService.partyBox.watch().listen((_) => _loadSilently());
  }

  @override
  void dispose() {
    SyncManager().isSyncingNotifier.removeListener(_onSyncStatusChanged);
    _entrySub?.cancel();
    _partySub?.cancel();
    super.dispose();
  }

  void _onSyncStatusChanged() {
    // Silently refresh when a sync cycle completes
    if (!SyncManager().isSyncingNotifier.value && mounted) {
      _loadSilently();
    }
  }

  void _loadSilently() {
    if (!mounted) return;
    setState(() {
      _stats         = LocalDbService.computeStats();
      _recentEntries = LocalDbService.getRecentEntries(limit: 5);
    });
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    // Local DB is the single source of truth — always instant, always offline-safe
    final localStats   = LocalDbService.computeStats();
    final recentLocal  = LocalDbService.getRecentEntries(limit: 5);
    if (mounted) {
      setState(() {
        _stats         = localStats;
        _recentEntries = recentLocal;
        _loading       = false;
      });
    }
    // Background: push local changes then pull from server
    SyncManager().performFullSync();
  }

  // ─── Helpers ───────────────────────────────────────────────────

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} hrs ago';
    return '${diff.inDays} days ago';
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'ACTIVE':    return Colors.green[700]!;
      case 'OVERDUE':   return Colors.orange[700]!;
      case 'WITHDRAWN': return Colors.blue[700]!;
      case 'CLOSED':    return Colors.grey[600]!;
      default:          return Colors.grey;
    }
  }

  Widget _statCard({
    required String label,
    required String value,
    required Color color,
    required IconData icon,
    VoidCallback? onTap,
  }) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: color, size: 20),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                  ),
                  if (onTap != null) ...[const Spacer(), Icon(Icons.chevron_right, size: 14, color: Colors.grey[400])],
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
      ),
    );
  }

  // ─── Online / Offline chip ─────────────────────────────────────

  Widget _connectivityChip() {
    return ValueListenableBuilder<bool>(
      valueListenable: SyncManager().isOnlineNotifier,
      builder: (context, isOnline, _) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          margin: const EdgeInsets.only(right: 8),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: isOnline
                ? Colors.green.withOpacity(0.15)
                : Colors.orange.withOpacity(0.15),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isOnline ? Icons.wifi : Icons.wifi_off,
                size: 13,
                color: isOnline ? Colors.green[700] : Colors.orange[700],
              ),
              const SizedBox(width: 4),
              Text(
                isOnline ? 'Online' : 'Offline',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isOnline ? Colors.green[700] : Colors.orange[700],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ─── Conflict Banner ───────────────────────────────────────────

  Widget _conflictBanner() {
    return ValueListenableBuilder<int>(
      valueListenable: SyncManager().pendingCountNotifier,
      builder: (context, _, __) {
        final conflictCount = SyncManager().getQueueStats()['conflict'] ?? 0;
        if (conflictCount == 0) return const SizedBox.shrink();
        
        return InkWell(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SyncDiagnosticsScreen()),
          ),
          child: Container(
            width: double.infinity,
            color: Colors.red.shade100,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 18),
                const SizedBox(width: 8),
                Text(
                  '$conflictCount operation(s) need attention',
                  style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.arrow_forward_ios, color: Colors.red, size: 12),
              ],
            ),
          ),
        );
      },
    );
  }

  // ─── Sync banner ───────────────────────────────────────────────

  Widget _syncBanner() {
    return ValueListenableBuilder<bool>(
      valueListenable: SyncManager().isSyncingNotifier,
      builder: (context, isSyncing, _) {
        if (!isSyncing) return const SizedBox.shrink();
        return Container(
          color: const Color(0xFF5C35D4).withOpacity(0.08),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF5C35D4))),
              SizedBox(width: 10),
              Text('Syncing…',
                  style: TextStyle(
                      color: Color(0xFF5C35D4),
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        );
      },
    );
  }

  // ─── Pending count badge ───────────────────────────────────────

  Widget _pendingBadge() {
    return ValueListenableBuilder<int>(
      valueListenable: SyncManager().pendingCountNotifier,
      builder: (context, count, _) {
        if (count == 0) return const SizedBox.shrink();
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.orange.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.orange.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              const Icon(Icons.cloud_upload_outlined, size: 14, color: Colors.orange),
              const SizedBox(width: 6),
              Text(
                '$count operation${count == 1 ? '' : 's'} pending sync',
                style: const TextStyle(
                    fontSize: 12, color: Colors.orange, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        );
      },
    );
  }

  // ─── Recent Activity ───────────────────────────────────────────

  Widget _recentActivitySection() {
    if (_recentEntries.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            'Recent Activity',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 8),
        ..._recentEntries.map((e) => _recentEntryTile(e)),
      ],
    );
  }

  Widget _recentEntryTile(Entry e) {
    // Use computed values — always live, offline-safe
    final payable    = e.computedTotalPayable;
    final daysLabel  = e.daysRemainingLabel;
    final color      = _statusColor(e.status);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => EntryDetailScreen(entry: e)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              // Status indicator dot
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text((e.id == null || e.id! < 0) ? 'SR: Pending ⟳' : e.srNumber,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 13)),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            e.partyName,
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[600]),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text('₹${payable.toStringAsFixed(0)}',
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w600)),
                        if (daysLabel.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              daysLabel,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: e.dueDateSeverity == 'red'
                                      ? Colors.red
                                      : e.dueDateSeverity == 'orange'
                                          ? Colors.orange
                                          : Colors.grey[600]),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              // Status chip
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(e.status,
                    style: TextStyle(
                        fontSize: 10,
                        color: color,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final businessName = SettingsService.businessName;
    final lastSynced = SettingsService.lastSyncedAt;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(businessName, style: const TextStyle(fontSize: 18)),
            Text(
              lastSynced != null ? 'Last synced: ${_timeAgo(lastSynced)}' : 'Never synced',
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ],
        ),
        actions: [
          _connectivityChip(),
          IconButton(
            icon: const Icon(Icons.analytics_outlined),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportsScreen())),
            tooltip: 'Reports & Analytics',
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: Column(
        children: [
          _conflictBanner(),
          _syncBanner(),
          _pendingBadge(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.all(12),
                      children: [
                        const SizedBox(height: 4),

                        // ── Overview Stats ──
                        Text('Overview',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 10),
                        GridView.count(
                          crossAxisCount: 2,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                          childAspectRatio: 1.55,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          children: [
                            _statCard(
                              label: 'Total Parties',
                              value: '${_stats!['total_parties']}',
                              color: const Color(0xFF5C35D4),
                              icon: Icons.people,
                              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PartyScreen())),
                            ),
                            _statCard(
                              label: 'Total Entries',
                              value: '${_stats!['total_entries']}',
                              color: Colors.blueGrey,
                              icon: Icons.receipt_long,
                              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FilteredEntryListScreen(title: 'All Entries'))),
                            ),
                            _statCard(
                              label: 'Active',
                              value: '${_stats!['active']}',
                              color: Colors.green[700]!,
                              icon: Icons.check_circle_outline,
                              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FilteredEntryListScreen(title: 'Active Entries', statusFilter: 'ACTIVE'))),
                            ),
                            _statCard(
                              label: 'Overdue',
                              value: '${_stats!['overdue']}',
                              color: Colors.orange[700]!,
                              icon: Icons.warning_amber_outlined,
                              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FilteredEntryListScreen(title: 'Overdue Entries', statusFilter: 'OVERDUE'))),
                            ),
                            _statCard(
                              label: 'Withdrawn',
                              value: '${_stats!['withdrawn']}',
                              color: Colors.blue[700]!,
                              icon: Icons.undo,
                              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FilteredEntryListScreen(title: 'Withdrawn Entries', statusFilter: 'WITHDRAWN'))),
                            ),
                            _statCard(
                              label: 'Closed',
                              value: '${_stats!['closed']}',
                              color: Colors.grey[600]!,
                              icon: Icons.lock_outline,
                              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FilteredEntryListScreen(title: 'Closed Entries', statusFilter: 'CLOSED'))),
                            ),
                          ],
                        ),

                        // ── Amounts ──
                        const SizedBox(height: 16),
                        Text('Amounts',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: _statCard(
                                label: 'Active Amount',
                                value:
                                    '₹${(_stats!['active_amount'] as double).toStringAsFixed(0)}',
                                color: Colors.green[700]!,
                                icon: Icons.currency_rupee,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _statCard(
                                label: 'Overdue Amount',
                                value:
                                    '₹${(_stats!['overdue_amount'] as double).toStringAsFixed(0)}',
                                color: Colors.orange[700]!,
                                icon: Icons.currency_rupee,
                              ),
                            ),
                          ],
                        ),

                        // ── Recent Activity ──
                        _recentActivitySection(),

                        const SizedBox(height: 80), // bottom padding for nav bar
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
