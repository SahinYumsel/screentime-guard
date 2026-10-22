import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants.dart';
import '../domain/rule.dart';
import '../domain/usage_record.dart';

/// SharedPreferences üzerinde cihaz kimliği, önbelleğe alınmış kural
/// ve çevrimdışı kullanım kuyruğunu (offline queue) saklayan yerel veri katmanı.
class LocalStore {
  final SharedPreferences _prefs;

  const LocalStore(this._prefs);

  // --- Sunucu Adresi (Gerçek cihazda LAN IP yapılandırması için) ---
  String getApiBaseUrl() {
    return _prefs.getString(AppConstants.keyApiBaseUrl) ??
        AppConstants.defaultBaseUrl;
  }

  Future<void> setApiBaseUrl(String url) async {
    final trimmed = url.trim().replaceAll(RegExp(r'/+$'), '');
    await _prefs.setString(AppConstants.keyApiBaseUrl, trimmed);
  }

  // --- Cihaz Kimliği & Token ---
  String? getDeviceToken() => _prefs.getString(AppConstants.keyDeviceToken);
  String? getDeviceId() => _prefs.getString(AppConstants.keyDeviceId);
  String getDeviceName() =>
      _prefs.getString(AppConstants.keyDeviceName) ?? 'Android Cihazım';

  Future<void> saveDeviceCredentials({
    required String deviceId,
    required String token,
    required String name,
  }) async {
    await _prefs.setString(AppConstants.keyDeviceId, deviceId);
    await _prefs.setString(AppConstants.keyDeviceToken, token);
    await _prefs.setString(AppConstants.keyDeviceName, name);
  }

  // --- Offline-First Kural Önbelleği ---
  Rule getCachedRule() {
    final raw = _prefs.getString(AppConstants.keyCachedRule);
    if (raw == null || raw.isEmpty) {
      return Rule.defaults();
    }
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return Rule.fromJson(decoded);
    } catch (_) {
      return Rule.defaults();
    }
  }

  Future<void> saveCachedRule(Rule rule) async {
    await _prefs.setString(
      AppConstants.keyCachedRule,
      jsonEncode(rule.toJson()),
    );
  }

  // --- Çevrimdışı Kullanım Kuyruğu (Offline Sync Queue) ---
  List<UsageRecord> getOfflineUsageQueue() {
    final raw = _prefs.getString(AppConstants.keyOfflineUsageQueue);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .whereType<Map>()
          .map((m) => UsageRecord.fromJson(Map<String, dynamic>.from(m)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Aynı tarihe ait kayıt varsa kuyrukta üzerine yazar, yoksa ekler (idempotent yerel kuyruk).
  Future<void> enqueueOfflineUsage(UsageRecord record) async {
    final queue = getOfflineUsageQueue();
    final idx = queue.indexWhere((item) => item.date == record.date);
    if (idx >= 0) {
      queue[idx] = record;
    } else {
      queue.add(record);
    }
    await _saveQueue(queue);
  }

  Future<void> removeOfflineUsageByDate(String date) async {
    final queue = getOfflineUsageQueue()
      ..removeWhere((item) => item.date == date);
    await _saveQueue(queue);
  }

  Future<void> _saveQueue(List<UsageRecord> queue) async {
    final encoded = jsonEncode(queue.map((e) => e.toJson()).toList());
    await _prefs.setString(AppConstants.keyOfflineUsageQueue, encoded);
  }

  // --- Tekrarlayan Uyarı Engelleme (Cooldown) ---
  String? getLastAlertState() =>
      _prefs.getString(AppConstants.keyLastAlertState);

  int? getLastAlertEpochMs() =>
      _prefs.getInt(AppConstants.keyLastAlertEpochMs);

  Future<void> saveLastAlert({
    required String stateCode,
    required int epochMs,
  }) async {
    await _prefs.setString(AppConstants.keyLastAlertState, stateCode);
    await _prefs.setInt(AppConstants.keyLastAlertEpochMs, epochMs);
  }
}
