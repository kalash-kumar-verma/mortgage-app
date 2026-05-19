import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../services/settings_service.dart';
import '../services/api_service.dart';
import '../services/local_db_service.dart';
import '../services/sync_manager.dart';
import '../models/business_setting.dart';
import '../models/sync_action.dart';
import 'login_screen.dart';
import 'sync_diagnostics_screen.dart';
import 'recycle_bin_screen.dart';
import 'profile_screen.dart';
import 'activity_history_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _loadingBusiness = true;
  bool _settingsOffline = false;
  BusinessSetting? _businessSetting;

  // Business rule state
  bool _strictMode   = false;
  bool _fiveDayLogic = false;
  int  _gracePeriod  = 5;

  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    _loadBackendSettings();
    _loadPackageInfo();
  }

  Future<void> _loadPackageInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _appVersion = 'v${info.version}+${info.buildNumber}');
    } catch (_) {
      if (mounted) setState(() => _appVersion = 'v1.0.0');
    }
  }

  Future<void> _loadBackendSettings() async {
    try {
      final setting = await ApiService()
          .fetchBusinessSettings()
          .timeout(const Duration(seconds: 6));
      if (mounted) {
        setState(() {
          _businessSetting = setting;
          _strictMode      = setting.strictMode;
          _fiveDayLogic    = setting.fiveDayLogic;
          _gracePeriod     = setting.gracePeriodDays;
          _loadingBusiness = false;
          _settingsOffline = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() { _loadingBusiness = false; _settingsOffline = true; });
    }
  }

  Future<void> _saveBusinessSettings() async {
    if (_businessSetting == null) return;
    try {
      final updated = BusinessSetting(
        id: _businessSetting!.id,
        strictMode: _strictMode,
        fiveDayLogic: _fiveDayLogic,
        gracePeriodDays: _gracePeriod,
      );
      await LocalDbService.saveBusinessSetting(updated);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to save: $e')));
      }
    }
  }

  Future<void> _clearSyncQueue() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Clear Sync Queue'),
        content: const Text(
            'Permanently deletes all pending offline changes that have not synced.\n\n'
            'Use only if you want to discard queued actions.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final box = Hive.box<SyncAction>(LocalDbService.syncBoxName);
    await box.clear();
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Sync queue cleared.')));
    }
  }

  Future<void> _logout() async {
    SyncManager().dispose();
    await LocalDbService.closeUserBoxes();
    await SettingsService.setToken(null);
    await SettingsService.setUsername(null);
    LocalDbService.setUserNamespace('');
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  Future<void> _logoutAllDevices() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Logout All Devices'),
        content: const Text('This will log out all other devices immediately.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Logout All', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await ApiService().logoutAllDevices();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('All other devices logged out.')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  // ─── Build helpers ────────────────────────────────────────────────

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 24, 4, 8),
        child: Text(
          title.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      );

  Widget _tile({
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
    Color? iconColor,
    Color? titleColor,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: (iconColor ?? scheme.primary).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: iconColor ?? scheme.primary),
        ),
        title: Text(title,
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: titleColor)),
        subtitle: subtitle != null
            ? Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey[500]))
            : null,
        trailing: trailing ??
            (onTap != null
                ? Icon(Icons.chevron_right, color: Colors.grey[400], size: 18)
                : null),
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _dividerTile() => const SizedBox(height: 2);

  // ─── Profile card ─────────────────────────────────────────────────

  Widget _profileCard() {
    final username     = SettingsService.username ?? 'User';
    final businessName = SettingsService.businessName;
    final initials     = username.isNotEmpty ? username[0].toUpperCase() : 'U';
    final scheme       = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [scheme.primary, scheme.primary.withValues(alpha: 0.7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ProfileScreen()),
          );
          if (mounted) setState(() {});
        },
        child: Row(
          children: [
            CircleAvatar(
              radius: 30,
              backgroundColor: Colors.white.withValues(alpha: 0.25),
              child: Text(initials,
                  style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(username,
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w700, fontSize: 17)),
                  const SizedBox(height: 2),
                  Text(businessName,
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8), fontSize: 13)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white, size: 24),
          ],
        ),
      ),
    );
  }


  Future<void> _editInterestRateDialog() async {
    final ctrl = TextEditingController(text: SettingsService.defaultInterest);
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Default Interest Rate'),
        content: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Rate (%)', suffixText: '%'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              await SettingsService.setDefaultInterest(ctrl.text.trim());
              if (mounted) { setState(() {}); Navigator.pop(context); }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _editPinDialog() async {
    final ctrl = TextEditingController(text: SettingsService.withdrawPin);
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Withdrawal PIN'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          obscureText: true,
          maxLength: 6,
          decoration: const InputDecoration(labelText: '4–6 digit PIN'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (ctrl.text.trim().length < 4) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('PIN must be at least 4 digits')));
                return;
              }
              await SettingsService.setWithdrawPin(ctrl.text.trim());
              if (mounted) { setState(() {}); Navigator.pop(context); }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _editApiUrlDialog() async {
    final ctrl = TextEditingController(text: SettingsService.apiBaseUrl);
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('API Base URL'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
              labelText: 'URL', helperText: 'e.g. https://yourapp.onrender.com/api'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              await SettingsService.setApiBaseUrl(ctrl.text.trim());
              if (mounted) Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _editGracePeriodDialog() async {
    final ctrl = TextEditingController(text: _gracePeriod.toString());
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Grace Period'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Days', helperText: 'Extra days before charging next month'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final v = int.tryParse(ctrl.text.trim()) ?? 5;
              setState(() => _gracePeriod = v);
              await _saveBusinessSettings();
              if (mounted) Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 48),
        children: [

          // ── Profile ──────────────────────────────────────────────
          _profileCard(),

          // ── General ──────────────────────────────────────────────
          _section('General'),
          _tile(
            icon: Icons.dark_mode_outlined,
            title: 'Dark Mode',
            trailing: ValueListenableBuilder<bool>(
              valueListenable: SettingsService.darkModeNotifier,
              builder: (_, isDark, __) => Switch(
                value: isDark,
                onChanged: (v) => SettingsService.setDarkMode(v),
              ),
            ),
          ),
          _dividerTile(),
          _tile(
            icon: Icons.percent_outlined,
            title: 'Default Interest Rate',
            subtitle: '${SettingsService.defaultInterest}% per month',
            onTap: _editInterestRateDialog,
          ),

          // ── Business Rules ────────────────────────────────────────
          _section('Business Rules'),
          if (_loadingBusiness)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_settingsOffline)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.cloud_off, color: Colors.orange[700], size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('Unavailable offline',
                        style: TextStyle(color: Colors.orange[700], fontSize: 13)),
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() { _loadingBusiness = true; _settingsOffline = false; });
                      _loadBackendSettings();
                    },
                    child: const Text('Retry'),
                  ),
                ],
              ),
            )
          else ...[
            _tile(
              icon: Icons.calculate_outlined,
              title: 'Strict Mode',
              subtitle: 'Exact daily interest calculation',
              trailing: Switch(
                value: _strictMode,
                onChanged: (v) {
                  setState(() => _strictMode = v);
                  _saveBusinessSettings();
                },
              ),
            ),
            _dividerTile(),
            _tile(
              icon: Icons.timer_outlined,
              title: '5-Day Logic',
              subtitle: 'No interest if withdrawn within 5 days',
              trailing: Switch(
                value: _fiveDayLogic,
                onChanged: (v) {
                  setState(() => _fiveDayLogic = v);
                  _saveBusinessSettings();
                },
              ),
            ),
            _dividerTile(),
            _tile(
              icon: Icons.date_range_outlined,
              title: 'Grace Period',
              subtitle: '$_gracePeriod days',
              onTap: _editGracePeriodDialog,
            ),
          ],

          // ── Security ──────────────────────────────────────────────
          _section('Security'),
          _tile(
            icon: Icons.lock_outlined,
            title: 'Withdrawal PIN',
            subtitle: '●●●●',
            onTap: _editPinDialog,
          ),
          _dividerTile(),
          _tile(
            icon: Icons.phonelink_lock_outlined,
            title: 'App Lock',
            subtitle: 'Coming soon',
            iconColor: Colors.grey,
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('Soon', style: TextStyle(fontSize: 11, color: Colors.grey)),
            ),
          ),

          // ── Data & Sync ───────────────────────────────────────────
          _section('Data & Sync'),
          _tile(
            icon: Icons.history,
            title: 'Activity History',
            subtitle: 'View audit trail and timeline',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ActivityHistoryScreen())),
          ),
          _dividerTile(),
          _tile(
            icon: Icons.delete_sweep_outlined,
            title: 'Recycle Bin',
            subtitle: 'View deleted records',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RecycleBinScreen())),
          ),
          _dividerTile(),
          _tile(
            icon: Icons.bug_report_outlined,
            title: 'Sync Diagnostics',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SyncDiagnosticsScreen())),
          ),
          _dividerTile(),
          _tile(
            icon: Icons.sync_outlined,
            title: 'Force Sync Now',
            onTap: () {
              SyncManager().performFullSync();
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Sync started…')));
            },
          ),
          _dividerTile(),
          ValueListenableBuilder<int>(
            valueListenable: SyncManager().pendingCountNotifier,
            builder: (_, count, __) => _tile(
              icon: Icons.cloud_upload_outlined,
              title: 'Pending Queue',
              subtitle: count == 0 ? 'All synced' : '$count operation${count == 1 ? '' : 's'} pending',
              trailing: count > 0
                  ? TextButton(
                      onPressed: _clearSyncQueue,
                      child: const Text('Clear', style: TextStyle(color: Colors.red)),
                    )
                  : Icon(Icons.check_circle_outline, color: Colors.green[700], size: 20),
            ),
          ),
          _dividerTile(),
          _tile(
            icon: Icons.settings_ethernet_outlined,
            title: 'API Base URL',
            subtitle: SettingsService.apiBaseUrl,
            onTap: _editApiUrlDialog,
          ),

          // ── Account ───────────────────────────────────────────────
          _section('Account'),
          _tile(
            icon: Icons.logout,
            title: 'Logout',
            iconColor: Colors.red[400],
            titleColor: Colors.red[400],
            onTap: _logout,
          ),
          _dividerTile(),
          _tile(
            icon: Icons.phonelink_erase_outlined,
            title: 'Logout All Devices',
            iconColor: Colors.red[300],
            titleColor: Colors.red[300],
            onTap: _logoutAllDevices,
          ),
          _dividerTile(),
          _tile(
            icon: Icons.person_remove_outlined,
            title: 'Delete Account',
            subtitle: 'Coming soon',
            iconColor: Colors.grey,
            titleColor: Colors.grey,
          ),

          // ── About ─────────────────────────────────────────────────
          _section('About'),
          _tile(
            icon: Icons.info_outlined,
            title: 'App Version',
            subtitle: _appVersion.isEmpty ? 'Loading…' : _appVersion,
          ),
          _dividerTile(),
          _tile(
            icon: Icons.help_outline,
            title: 'Help & Support',
            subtitle: 'Coming soon',
            iconColor: Colors.grey,
          ),
          _dividerTile(),
          _tile(
            icon: Icons.share_outlined,
            title: 'Invite Friends',
            subtitle: 'Coming soon',
            iconColor: Colors.grey,
          ),
          _dividerTile(),
          _tile(
            icon: Icons.system_update_outlined,
            title: 'Check for Updates',
            subtitle: 'Coming soon',
            iconColor: Colors.grey,
          ),
          _dividerTile(),
          _tile(
            icon: Icons.diamond_outlined,
            title: 'About Jewellery Mortgage',
            subtitle: 'Offline-first mortgage management',
            iconColor: scheme.primary,
          ),

          const SizedBox(height: 16),
          Center(
            child: Text(
              'Made with ♥ for jewellery businesses',
              style: TextStyle(fontSize: 12, color: Colors.grey[400]),
            ),
          ),
        ],
      ),
    );
  }
}
