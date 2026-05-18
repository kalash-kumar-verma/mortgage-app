import 'package:hive_flutter/hive_flutter.dart';

class SettingsService {
  static const _boxName = 'settings';

  static Box get _box => Hive.box(_boxName);

  // API base URL
  static String get apiBaseUrl =>
      _box.get('apiBaseUrl', defaultValue: 'http://192.168.137.196:8000/api');

  static Future<void> setApiBaseUrl(String url) =>
      _box.put('apiBaseUrl', url);

  // Auth Token
  static String? get token => _box.get('token');

  static Future<void> setToken(String? token) {
    if (token == null) {
      return _box.delete('token');
    }
    return _box.put('token', token);
  }

  // Username
  static String? get username => _box.get('username');

  static Future<void> setUsername(String? username) {
    if (username == null) {
      return _box.delete('username');
    }
    return _box.put('username', username);
  }

  // Business name
  static String get businessName =>
      _box.get('businessName', defaultValue: 'Jewellery Mortgage');

  static Future<void> setBusinessName(String name) =>
      _box.put('businessName', name);

  // Withdraw PIN (simple 4-digit PIN, default 1234)
  static String get withdrawPin =>
      _box.get('withdrawPin', defaultValue: '1234');

  static Future<void> setWithdrawPin(String pin) =>
      _box.put('withdrawPin', pin);

  // Default interest rate
  static String get defaultInterest =>
      _box.get('defaultInterest', defaultValue: '2.0');

  static Future<void> setDefaultInterest(String rate) =>
      _box.put('defaultInterest', rate);

  // Last Synced Timestamp
  static DateTime? get lastSyncedAt {
    final iso = _box.get('last_synced_at');
    return iso != null ? DateTime.tryParse(iso) : null;
  }

  static Future<void> setLastSyncedAt(DateTime dt) =>
      _box.put('last_synced_at', dt.toIso8601String());
}
