import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../services/settings_service.dart';
import '../services/local_db_service.dart';
import '../services/sync_manager.dart';
import '../main.dart';
import 'settings_screen.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _login() async {
    final lockUntil = SettingsService.loginLockUntil;
    if (lockUntil != null && DateTime.now().isBefore(lockUntil)) {
      final diff = lockUntil.difference(DateTime.now()).inMinutes;
      setState(() => _error = 'Too many failed attempts. Try again in ${diff + 1} minutes.');
      return;
    }

    setState(() { _loading = true; _error = null; });
    final baseUrl = SettingsService.apiBaseUrl;

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/login/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': _usernameController.text,
          'password': _passwordController.text,
        }),
      );

      if (response.statusCode == 200) {
        // Reset throttling
        await SettingsService.setFailedLoginAttempts(0);
        await SettingsService.setLoginLockUntil(null);

        final data  = jsonDecode(response.body);
        final token = data['token'] as String;
        final username = _usernameController.text.trim();

        await SettingsService.setToken(token);
        await SettingsService.setUsername(username);

        // Set user namespace and open user-scoped Hive boxes BEFORE navigating
        LocalDbService.setUserNamespace(username);
        await LocalDbService.openUserBoxes();

        // Start background sync
        final syncManager = SyncManager();
        syncManager.initialize();
        syncManager.performFullSync(); // fire-and-forget

        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const MainShell()),
          );
        }
      } else {
        int attempts = SettingsService.failedLoginAttempts + 1;
        await SettingsService.setFailedLoginAttempts(attempts);
        
        if (attempts >= 5) {
          await SettingsService.setLoginLockUntil(DateTime.now().add(const Duration(minutes: 5)));
          setState(() => _error = 'Too many failed attempts. Try again in 5 minutes.');
        } else {
          setState(() => _error = 'Invalid username or password (${5 - attempts} attempts left)');
        }
      }
    } catch (e) {
      setState(() => _error = 'Network error: Please check server URL and connection');
    }
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF5C35D4), Color(0xFF3B1D96)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
                  icon: const Icon(Icons.settings, color: Colors.white),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SettingsScreen()),
                    );
                  },
                ),
              ),
              Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              elevation: 12,
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.diamond_outlined, size: 64, color: Color(0xFF5C35D4)),
                    const SizedBox(height: 16),
                    Text(
                      SettingsService.businessName,
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    const Text('Please login to continue', style: TextStyle(color: Colors.grey)),
                    const SizedBox(height: 32),
                    if (_error != null) ...[
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                      ),
                      const SizedBox(height: 16),
                    ],
                    TextField(
                      controller: _usernameController,
                      decoration: InputDecoration(
                        labelText: 'Username',
                        prefixIcon: const Icon(Icons.person),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _passwordController,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _loading ? null : _login,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF5C35D4),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: _loading
                            ? const CircularProgressIndicator(color: Colors.white)
                            : const Text('Login', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text("Don't have an account? ", style: TextStyle(color: Colors.grey)),
                        TextButton(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const RegisterScreen()),
                          ),
                          child: const Text(
                            'Register',
                            style: TextStyle(
                              color: Color(0xFF5C35D4),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
