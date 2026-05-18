import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import '../services/settings_service.dart';
import '../services/api_service.dart';
import '../services/local_db_service.dart';
import '../services/sync_manager.dart';
import '../models/business_setting.dart';
import '../models/sync_action.dart';
import 'login_screen.dart';
import 'sync_diagnostics_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _apiUrlController = TextEditingController(text: SettingsService.apiBaseUrl);
  final _businessNameController = TextEditingController(text: SettingsService.businessName);
  final _pinController = TextEditingController(text: SettingsService.withdrawPin);
  
  bool _loading = true;
  bool _saving = false;
  BusinessSetting? _businessSetting;
  
  // Local state for backend settings
  bool _strictMode = false;
  bool _fiveDayLogic = false;
  final _gracePeriodController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadBackendSettings();
  }

  bool _settingsOffline = false;

  Future<void> _loadBackendSettings() async {
    try {
      final setting = await ApiService().fetchBusinessSettings()
          .timeout(const Duration(seconds: 5));
      if (mounted) {
        setState(() {
          _businessSetting = setting;
          _strictMode = setting.strictMode;
          _fiveDayLogic = setting.fiveDayLogic;
          _gracePeriodController.text = setting.gracePeriodDays.toString();
          _loading = false;
          _settingsOffline = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _settingsOffline = true; // Show offline notice in UI
        });
      }
    }
  }

  @override
  void dispose() {
    _apiUrlController.dispose();
    _businessNameController.dispose();
    _pinController.dispose();
    _gracePeriodController.dispose();
    super.dispose();
  }

  Widget _queueStat(String label, int count, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8, height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text('$count $label', style: TextStyle(fontSize: 12, color: Colors.grey[700])),
      ],
    );
  }

  Future<void> _saveSettings() async {
    setState(() => _saving = true);
    
    // Save local Hive settings
    SettingsService.setApiBaseUrl(_apiUrlController.text);
    SettingsService.setBusinessName(_businessNameController.text);
    SettingsService.setWithdrawPin(_pinController.text);
    
    // Save Backend Business Settings if loaded
    if (_businessSetting != null) {
      try {
        final newSetting = BusinessSetting(
          id: _businessSetting!.id,
          strictMode: _strictMode,
          fiveDayLogic: _fiveDayLogic,
          gracePeriodDays: int.tryParse(_gracePeriodController.text) ?? 5,
        );
        await LocalDbService.saveBusinessSetting(newSetting);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save business settings: $e')));
        }
      }
    }
    
    if (mounted) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settings saved successfully!')),
      );
    }
  }

  Future<void> _clearSyncQueue() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Clear Pending Sync Queue'),
        content: const Text(
          'This will permanently delete all pending offline changes that have not been synced to the server.\n\n'
          'Use this only if you want to discard old queued actions. Recent offline data in your app will NOT be deleted.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear Queue', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final box = Hive.box<SyncAction>(LocalDbService.syncBoxName);
    await box.clear();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sync queue cleared. Fresh actions will sync normally.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Interest Business Rules (Backend)
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_settingsOffline)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    const Icon(Icons.cloud_off, size: 40, color: Colors.grey),
                    const SizedBox(height: 8),
                    const Text('Business Rules unavailable offline', style: TextStyle(color: Colors.grey)),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed: () {
                        setState(() { _loading = true; _settingsOffline = false; });
                        _loadBackendSettings();
                      },
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          else if (_businessSetting != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Interest Calculation Rules', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    SwitchListTile(
                      title: const Text('Strict Mode (Exact Days)'),
                      subtitle: const Text('Calculates exact interest per day instead of per month.'),
                      value: _strictMode,
                      onChanged: (v) => setState(() => _strictMode = v),
                    ),
                    SwitchListTile(
                      title: const Text('5-Day Logic'),
                      subtitle: const Text('If withdrawn within 5 days of start, charge 0 interest.'),
                      value: _fiveDayLogic,
                      onChanged: (v) => setState(() => _fiveDayLogic = v),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _gracePeriodController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Grace Period (Days)',
                        helperText: 'Number of extra days allowed before charging next month.',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
          // App Settings (Local)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('General Settings', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _businessNameController,
                    decoration: const InputDecoration(
                      labelText: 'Business Name',
                      helperText: 'Displayed on the dashboard',
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Security', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _pinController,
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    maxLength: 4,
                    decoration: const InputDecoration(
                      labelText: 'Withdrawal PIN',
                      helperText: '4-digit PIN required to withdraw entries',
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Advanced', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _apiUrlController,
                    decoration: const InputDecoration(
                      labelText: 'API Base URL',
                      helperText: 'e.g., http://192.168.1.100:8000/api',
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Sync queue status
                  ValueListenableBuilder<int>(
                    valueListenable: SyncManager().pendingCountNotifier,
                    builder: (context, count, _) {
                      final stats = SyncManager().getQueueStats();
                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey[200]!),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Sync Queue',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            const SizedBox(height: 8),
                            Row(children: [
                              _queueStat('Pending', stats['pending'] ?? 0, Colors.blue),
                              const SizedBox(width: 12),
                              _queueStat('Failed', stats['failed'] ?? 0, Colors.orange),
                              const SizedBox(width: 12),
                              _queueStat('Abandoned', stats['abandoned'] ?? 0, Colors.red),
                            ]),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: () => SyncManager().performFullSync(),
                    icon: const Icon(Icons.sync),
                    label: const Text('Force Sync Now'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SyncDiagnosticsScreen()),
                    ),
                    icon: const Icon(Icons.bug_report_outlined),
                    label: const Text('Open Sync Diagnostics'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                    onPressed: _clearSyncQueue,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Clear Pending Sync Queue'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _saving ? null : _saveSettings,
            icon: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.save),
            label: const Text('Save Settings'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: const Color(0xFF5C35D4),
            ),
          ),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: () async {
              // Proper logout: stop sync, close user boxes, clear credentials
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
            },
            icon: const Icon(Icons.logout, color: Colors.red),
            label: const Text('Logout', style: TextStyle(color: Colors.red)),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
          const Divider(),
          TextButton.icon(
            onPressed: () async {
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
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('All other devices logged out.')));
                }
              } catch (e) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
              }
            },
            icon: const Icon(Icons.phonelink_erase, color: Colors.red),
            label: const Text('Logout from all other devices', style: TextStyle(color: Colors.red)),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ],
      ),
    );
  }
}
