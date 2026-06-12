import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SettingsService {
  static const _boxName = 'settings';
  static Box get _box => Hive.box(_boxName);
  
  static const FlutterSecureStorage _secure = FlutterSecureStorage();
  
  static String? _token;
  static String _withdrawPin = '1234';

  static Future<void> initSecureStorage() async {
    _token = await _secure.read(key: 'token');
    _withdrawPin = await _secure.read(key: 'withdrawPin') ?? '1234';
    
    // Migration: If they exist in Hive but not secure storage, move them
    if (_token == null && _box.containsKey('token')) {
      _token = _box.get('token');
      await _secure.write(key: 'token', value: _token);
      await _box.delete('token');
    }
    
    if (await _secure.read(key: 'withdrawPin') == null && _box.containsKey('withdrawPin')) {
      _withdrawPin = _box.get('withdrawPin');
      await _secure.write(key: 'withdrawPin', value: _withdrawPin);
      await _box.delete('withdrawPin');
    }
  }

  // ─── Reactive notifiers ──────────────────────────────────────────
  /// Dark mode notifier — listen to this in MaterialApp for reactive theme switching.
  static final ValueNotifier<bool> darkModeNotifier = ValueNotifier<bool>(false);

  /// Call after Hive is open to prime the notifier from persisted value.
  static void initNotifiers() {
    darkModeNotifier.value = darkMode;
  }

  // ─── API ────────────────────────────────────────────────────────
  static String get apiBaseUrl =>
      _box.get('apiBaseUrl', defaultValue: 'https://mortgage-api-l4sf.onrender.com/api');

  static Future<void> setApiBaseUrl(String url) => _box.put('apiBaseUrl', url);

  static String? get token => _token;

  static Future<void> setToken(String? token) async {
    _token = token;
    if (token == null) {
      await _secure.delete(key: 'token');
    } else {
      await _secure.write(key: 'token', value: token);
    }
  }

  static String? get username => _box.get('username');

  static Future<void> setUsername(String? username) {
    if (username == null) return _box.delete('username');
    return _box.put('username', username);
  }

  static String get role => _box.get('role', defaultValue: 'owner');
  static Future<void> setRole(String role) => _box.put('role', role);

  // ─── Display ────────────────────────────────────────────────────
  static String get businessName =>
      _box.get('businessName', defaultValue: 'Jewellery Mortgage');

  static Future<void> setBusinessName(String name) => _box.put('businessName', name);

  // ─── Security ───────────────────────────────────────────────────
  static String get withdrawPin => _withdrawPin;

  static Future<void> setWithdrawPin(String pin) async {
    _withdrawPin = pin;
    await _secure.write(key: 'withdrawPin', value: pin);
  }

  static bool get appLockEnabled => _box.get('appLockEnabled', defaultValue: false);

  static Future<void> setAppLockEnabled(bool v) => _box.put('appLockEnabled', v);

  // Timeout in seconds (default 1 min = 60)
  static int get inactivityTimeout => _box.get('inactivityTimeout', defaultValue: 60);

  static Future<void> setInactivityTimeout(int seconds) => _box.put('inactivityTimeout', seconds);

  // ─── Login Throttling ───────────────────────────────────────────
  static int get failedLoginAttempts => _box.get('failedLoginAttempts', defaultValue: 0);
  
  static Future<void> setFailedLoginAttempts(int attempts) => _box.put('failedLoginAttempts', attempts);

  static DateTime? get loginLockUntil {
    final iso = _box.get('loginLockUntil');
    return iso != null ? DateTime.tryParse(iso) : null;
  }

  static Future<void> setLoginLockUntil(DateTime? dt) {
    if (dt == null) return _box.delete('loginLockUntil');
    return _box.put('loginLockUntil', dt.toIso8601String());
  }

  // ─── Preferences ────────────────────────────────────────────────
  static String get defaultInterest => _box.get('defaultInterest', defaultValue: '2.0');

  static Future<void> setDefaultInterest(String rate) => _box.put('defaultInterest', rate);

  static bool get darkMode => _box.get('darkMode', defaultValue: false);

  static Future<void> setDarkMode(bool v) async {
    await _box.put('darkMode', v);
    darkModeNotifier.value = v;
  }

  // ─── Sync timestamp ─────────────────────────────────────────────
  static DateTime? get lastSyncedAt {
    final iso = _box.get('last_synced_at');
    return iso != null ? DateTime.tryParse(iso) : null;
  }

  static Future<void> setLastSyncedAt(DateTime dt) =>
      _box.put('last_synced_at', dt.toIso8601String());
}
