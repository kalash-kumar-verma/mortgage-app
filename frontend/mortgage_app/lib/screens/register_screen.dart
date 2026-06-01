import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../services/settings_service.dart';
import '../services/local_db_service.dart';
import '../services/sync_manager.dart';
import '../main.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey          = GlobalKey<FormState>();
  final _usernameCtrl     = TextEditingController();
  final _emailCtrl        = TextEditingController();
  final _passwordCtrl     = TextEditingController();
  final _confirmPassCtrl  = TextEditingController();
  bool _loading           = false;
  bool _obscurePass       = true;
  bool _obscureConfirm    = true;
  String? _error;

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPassCtrl.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_passwordCtrl.text != _confirmPassCtrl.text) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }

    setState(() { _loading = true; _error = null; });

    final baseUrl = SettingsService.apiBaseUrl;

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/register/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': _usernameCtrl.text.trim(),
          'password': _passwordCtrl.text,
          'email':    _emailCtrl.text.trim(),
        }),
      ).timeout(const Duration(seconds: 60));

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 201) {
        // Registration succeeded — store token and auto-navigate to app
        final token    = data['token'] as String;
        final username = data['username'] as String;

        await SettingsService.setToken(token);
        await SettingsService.setUsername(username);

        // Open user-scoped Hive boxes
        LocalDbService.setUserNamespace(username);
        await LocalDbService.openUserBoxes();

        SyncManager().initialize();

        if (mounted) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const MainShell()),
            (_) => false,
          );
        }
      } else {
        final msg = data['error'] as String? ??
            data['detail'] as String? ??
            'Registration failed. Please try again.';
        setState(() => _error = msg);
      }
    } on Exception catch (e) {
      setState(() => _error = 'Network error: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
              // Back button
              Positioned(
                top: 8, left: 8,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
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
                      child: Form(
                        key: _formKey,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Header
                            const Icon(Icons.person_add_outlined, size: 56, color: Color(0xFF5C35D4)),
                            const SizedBox(height: 12),
                            const Text(
                              'Create Account',
                              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Register to start managing your mortgage records',
                              style: TextStyle(color: Colors.grey, fontSize: 12),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 24),

                            // Error banner
                            if (_error != null) ...[
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.red.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.red.withOpacity(0.3)),
                                ),
                                child: Text(
                                  _error!,
                                  style: const TextStyle(color: Colors.red, fontSize: 12),
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],

                            // Username
                            TextFormField(
                              controller: _usernameCtrl,
                              textInputAction: TextInputAction.next,
                              decoration: InputDecoration(
                                labelText: 'Username *',
                                prefixIcon: const Icon(Icons.person_outline),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                helperText: 'Min 3 characters, letters and numbers only',
                              ),
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) return 'Username is required';
                                if (v.trim().length < 3) return 'Username must be at least 3 characters';
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),

                            // Email (optional)
                            TextFormField(
                              controller: _emailCtrl,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              decoration: InputDecoration(
                                labelText: 'Email (Optional)',
                                prefixIcon: const Icon(Icons.email_outlined),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              validator: (v) {
                                if (v != null && v.trim().isNotEmpty) {
                                  final emailRegex = RegExp(r'^[\w\.\-]+@[\w\-]+\.\w+$');
                                  if (!emailRegex.hasMatch(v.trim())) return 'Enter a valid email address';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),

                            // Password
                            TextFormField(
                              controller: _passwordCtrl,
                              obscureText: _obscurePass,
                              textInputAction: TextInputAction.next,
                              decoration: InputDecoration(
                                labelText: 'Password *',
                                prefixIcon: const Icon(Icons.lock_outline),
                                suffixIcon: IconButton(
                                  icon: Icon(_obscurePass ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                                  onPressed: () => setState(() => _obscurePass = !_obscurePass),
                                ),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                helperText: 'Minimum 6 characters',
                              ),
                              validator: (v) {
                                if (v == null || v.isEmpty) return 'Password is required';
                                if (v.length < 6) return 'Password must be at least 6 characters';
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),

                            // Confirm Password
                            TextFormField(
                              controller: _confirmPassCtrl,
                              obscureText: _obscureConfirm,
                              textInputAction: TextInputAction.done,
                              onFieldSubmitted: (_) => _loading ? null : _register(),
                              decoration: InputDecoration(
                                labelText: 'Confirm Password *',
                                prefixIcon: const Icon(Icons.lock_outline),
                                suffixIcon: IconButton(
                                  icon: Icon(_obscureConfirm ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                                  onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                                ),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              validator: (v) {
                                if (v == null || v.isEmpty) return 'Please confirm your password';
                                if (v != _passwordCtrl.text) return 'Passwords do not match';
                                return null;
                              },
                            ),
                            const SizedBox(height: 28),

                            // Register button
                            SizedBox(
                              width: double.infinity,
                              height: 50,
                              child: ElevatedButton(
                                onPressed: _loading ? null : _register,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF5C35D4),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                child: _loading
                                    ? const CircularProgressIndicator(color: Colors.white)
                                    : const Text(
                                        'Create Account',
                                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                      ),
                              ),
                            ),
                            const SizedBox(height: 16),

                            // Back to login
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Text('Already have an account? ', style: TextStyle(color: Colors.grey)),
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text(
                                    'Login',
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
              ),
            ],
          ),
        ),
      ),
    );
  }
}
