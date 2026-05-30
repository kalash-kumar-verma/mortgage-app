import 'package:flutter/material.dart';
import '../services/security_service.dart';

class AppLockWrapper extends StatefulWidget {
  final Widget child;
  const AppLockWrapper({super.key, required this.child});

  @override
  State<AppLockWrapper> createState() => _AppLockWrapperState();
}

class _AppLockWrapperState extends State<AppLockWrapper> {
  @override
  void initState() {
    super.initState();
    SecurityService.instance.initialize();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => SecurityService.instance.recordActivity(),
      onPanDown: (_) => SecurityService.instance.recordActivity(),
      child: ValueListenableBuilder<bool>(
        valueListenable: SecurityService.instance.isLockedNotifier,
        builder: (context, isLocked, _) {
          if (isLocked) {
            return const AppLockScreen();
          }
          return widget.child;
        },
      ),
    );
  }
}

class AppLockScreen extends StatefulWidget {
  const AppLockScreen({super.key});

  @override
  State<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends State<AppLockScreen> {
  String _pin = '';
  String _error = '';

  @override
  void initState() {
    super.initState();
    _promptBiometric();
  }

  Future<void> _promptBiometric() async {
    final available = await SecurityService.instance.isBiometricAvailable();
    if (available) {
      final success = await SecurityService.instance.authenticateWithBiometrics();
      if (success) {
        SecurityService.instance.unlockApp();
      }
    }
  }

  void _onDigit(String digit) {
    if (_pin.length < 4) {
      setState(() {
        _pin += digit;
        _error = '';
      });
      if (_pin.length == 4) {
        _verify();
      }
    }
  }

  void _onDelete() {
    if (_pin.isNotEmpty) {
      setState(() {
        _pin = _pin.substring(0, _pin.length - 1);
        _error = '';
      });
    }
  }

  void _verify() {
    if (SecurityService.instance.verifyPin(_pin)) {
      SecurityService.instance.unlockApp();
    } else {
      setState(() {
        _error = 'Incorrect PIN';
        _pin = '';
      });
    }
  }

  Widget _buildKeypadButton(String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(40),
      child: Container(
        width: 80,
        height: 80,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.grey.withValues(alpha: 0.1),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lock_outline, size: 64, color: Colors.blue),
            const SizedBox(height: 24),
            const Text('App Locked', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('Enter PIN to unlock', style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(4, (index) {
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: index < _pin.length ? Colors.blue : Colors.grey.withValues(alpha: 0.3),
                  ),
                );
              }),
            ),
            const SizedBox(height: 16),
            Text(_error, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
            const SizedBox(height: 48),
            
            // Keypad
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildKeypadButton('1', () => _onDigit('1')),
                _buildKeypadButton('2', () => _onDigit('2')),
                _buildKeypadButton('3', () => _onDigit('3')),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildKeypadButton('4', () => _onDigit('4')),
                _buildKeypadButton('5', () => _onDigit('5')),
                _buildKeypadButton('6', () => _onDigit('6')),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildKeypadButton('7', () => _onDigit('7')),
                _buildKeypadButton('8', () => _onDigit('8')),
                _buildKeypadButton('9', () => _onDigit('9')),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  onPressed: _promptBiometric,
                  icon: const Icon(Icons.fingerprint, size: 32, color: Colors.blue),
                ),
                _buildKeypadButton('0', () => _onDigit('0')),
                IconButton(
                  onPressed: _onDelete,
                  icon: const Icon(Icons.backspace_outlined, size: 28),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
