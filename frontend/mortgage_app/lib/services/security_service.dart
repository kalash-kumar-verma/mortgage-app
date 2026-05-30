import 'dart:async';
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter/services.dart';

import 'settings_service.dart';

class SecurityService {
  static final SecurityService instance = SecurityService._internal();
  SecurityService._internal();

  final LocalAuthentication _auth = LocalAuthentication();

  DateTime? _lastActiveTime;
  Timer? _inactivityTimer;

  // Stream/Notifier to tell the app to show lock screen
  final ValueNotifier<bool> isLockedNotifier = ValueNotifier<bool>(false);

  void initialize() {
    _lastActiveTime = DateTime.now();
    _startInactivityTimer();
  }

  void recordActivity() {
    _lastActiveTime = DateTime.now();
    if (!isLockedNotifier.value) {
      _startInactivityTimer();
    }
  }

  void _startInactivityTimer() {
    _inactivityTimer?.cancel();
    if (!SettingsService.appLockEnabled) return;

    final timeout = Duration(seconds: SettingsService.inactivityTimeout);
    _inactivityTimer = Timer(timeout, () {
      if (!isLockedNotifier.value && SettingsService.appLockEnabled) {
        lockApp();
      }
    });
  }

  void lockApp() {
    if (!SettingsService.appLockEnabled) return;
    isLockedNotifier.value = true;
  }

  void unlockApp() {
    isLockedNotifier.value = false;
    recordActivity();
  }

  Future<bool> isBiometricAvailable() async {
    try {
      return await _auth.canCheckBiometrics || await _auth.isDeviceSupported();
    } on PlatformException catch (_) {
      return false;
    }
  }

  Future<bool> authenticateWithBiometrics() async {
    try {
      return await _auth.authenticate(
        localizedReason: 'Authenticate to unlock the app',
      );
    } on PlatformException catch (_) {
      return false;
    }
  }

  bool verifyPin(String pin) {
    return pin == SettingsService.withdrawPin;
  }
}
