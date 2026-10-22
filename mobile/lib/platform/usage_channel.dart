import 'package:flutter/services.dart';

import '../core/constants.dart';
import '../domain/usage_record.dart';

/// Android izin durumlarını tutan veri modeli.
class PermissionStatusSnapshot {
  final bool hasUsageStatsPermission;
  final bool hasOverlayPermission;
  final bool hasNotificationPermission;
  final bool isMonitoringActive;

  const PermissionStatusSnapshot({
    this.hasUsageStatsPermission = false,
    this.hasOverlayPermission = false,
    this.hasNotificationPermission = false,
    this.isMonitoringActive = false,
  });

  bool get allCriticalGranted => hasUsageStatsPermission;

  factory PermissionStatusSnapshot.fromMap(Map<dynamic, dynamic> map) {
    return PermissionStatusSnapshot(
      hasUsageStatsPermission: map['usageStats'] == true,
      hasOverlayPermission: map['overlay'] == true,
      hasNotificationPermission: map['notifications'] == true,
      isMonitoringActive: map['monitoringActive'] == true,
    );
  }
}

/// Kotlin native katmanı (UsageReader, MonitorService, OverlayManager) ile
/// Dart arasındaki MethodChannel sarmalayıcısı.
class UsageChannel {
  final MethodChannel _channel =
      const MethodChannel(AppConstants.methodChannelName);

  void Function(UsageRecord record)? _onPeriodicUsageCallback;

  UsageChannel() {
    _channel.setMethodCallHandler(_handleNativeCallback);
  }

  /// Kotlin MonitorService 60 saniyede bir kullanım verisi gönderdiğinde tetiklenir.
  void setOnPeriodicUsageUpdate(void Function(UsageRecord record)? callback) {
    _onPeriodicUsageCallback = callback;
  }

  Future<dynamic> _handleNativeCallback(MethodCall call) async {
    if (call.method == 'onUsageTick' && call.arguments is Map) {
      final map = Map<String, dynamic>.from(call.arguments as Map);
      final record = UsageRecord.fromJson(map);
      _onPeriodicUsageCallback?.call(record);
    }
    return null;
  }

  /// Bugünkü toplam ekran süresini ve en çok kullanılan uygulamaları Kotlin'den okur.
  Future<UsageRecord> getTodayUsage() async {
    try {
      final result =
          await _channel.invokeMapMethod<String, dynamic>('getTodayUsage');
      if (result != null) {
        return UsageRecord.fromJson(result);
      }
    } on PlatformException {
      // Native katman henüz bağlanmadığında veya izin yokken varsayılan boş kayıt
    } on MissingPluginException {
      // Test ortamı veya emülatör başlangıcı
    }
    return UsageRecord(
      date: UsageRecord.formatDate(DateTime.now()),
      totalMinutes: 0,
      topApps: const [],
    );
  }

  /// İzinlerin mevcut durumunu kontrol eder.
  Future<PermissionStatusSnapshot> checkPermissions() async {
    try {
      final result =
          await _channel.invokeMapMethod<String, dynamic>('checkPermissions');
      if (result != null) {
        return PermissionStatusSnapshot.fromMap(result);
      }
    } catch (_) {}
    return const PermissionStatusSnapshot();
  }

  /// Kullanım erişimi (PACKAGE_USAGE_STATS) ayarlar ekranını açar.
  Future<void> openUsageAccessSettings() async {
    try {
      await _channel.invokeMethod<void>('openUsageAccessSettings');
    } catch (_) {}
  }

  /// Ekran üstü gösterim (SYSTEM_ALERT_WINDOW) izin ekranını açar.
  Future<void> openOverlaySettings() async {
    try {
      await _channel.invokeMethod<void>('openOverlaySettings');
    } catch (_) {}
  }

  /// Android 13+ bildirim iznini (POST_NOTIFICATIONS) ister.
  Future<void> requestNotificationPermission() async {
    try {
      await _channel.invokeMethod<void>('requestNotificationPermission');
    } catch (_) {}
  }

  /// Arka planda 60 saniyede bir kontrol yapan MonitorService'i başlatır.
  Future<bool> startMonitorService() async {
    try {
      final started =
          await _channel.invokeMethod<bool>('startMonitorService');
      return started ?? false;
    } catch (_) {
      return false;
    }
  }

  /// MonitorService'i durdurur.
  Future<bool> stopMonitorService() async {
    try {
      final stopped = await _channel.invokeMethod<bool>('stopMonitorService');
      return stopped ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Kural ihlalinde bildirim veya ekran üstü uyarı (overlay) tetikler.
  Future<void> triggerUserAlert({
    required String title,
    required String message,
    required String mode, // 'notify' | 'overlay'
  }) async {
    try {
      await _channel.invokeMethod<void>('triggerAlert', {
        'title': title,
        'message': message,
        'mode': mode,
      });
    } catch (_) {}
  }
}
