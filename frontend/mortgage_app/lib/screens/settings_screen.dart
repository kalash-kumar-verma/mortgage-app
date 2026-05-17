import 'package:flutter/material.dart';
import '../services/settings_service.dart';
import '../services/api_service.dart';
import '../models/business_setting.dart';
import 'login_screen.dart';

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

  Future<void> _loadBackendSettings() async {
    try {
      final setting = await ApiService().fetchBusinessSettings();
      if (mounted) {
        setState(() {
          _businessSetting = setting;
          _strictMode = setting.strictMode;
          _fiveDayLogic = setting.fiveDayLogic;
          _gracePeriodController.text = setting.gracePeriodDays.toString();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        // Silently fail if backend is unreachable, just show UI.
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
        await ApiService().updateBusinessSettings(newSetting);
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
              await SettingsService.setToken(null);
              await SettingsService.setUsername(null);
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
        ],
      ),
    );
  }
}
