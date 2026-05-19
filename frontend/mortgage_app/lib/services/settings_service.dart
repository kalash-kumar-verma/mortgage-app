import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

class SettingsService {
  static const _boxName = 'settings';

  static Box get _box => Hive.box(_boxName);

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

  // ─── Auth ───────────────────────────────────────────────────────
  static String? get token => _box.get('token');

  static Future<void> setToken(String? token) {
    if (token == null) return _box.delete('token');
    return _box.put('token', token);
  }

  static String? get username => _box.get('username');

  static Future<void> setUsername(String? username) {
    if (username == null) return _box.delete('username');
    return _box.put('username', username);
  }

  // ─── Display ────────────────────────────────────────────────────
  static String get businessName =>
      _box.get('businessName', defaultValue: 'Jewellery Mortgage');

  static Future<void> setBusinessName(String name) => _box.put('businessName', name);

  // ─── Security ───────────────────────────────────────────────────
  static String get withdrawPin => _box.get('withdrawPin', defaultValue: '1234');

  static Future<void> setWithdrawPin(String pin) => _box.put('withdrawPin', pin);

  static bool get appLockEnabled => _box.get('appLockEnabled', defaultValue: false);

  static Future<void> setAppLockEnabled(bool v) => _box.put('appLockEnabled', v);

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
