/// Uygulama genelinde kullanılan sabitler.
class AppConstants {
  AppConstants._();

  /// Varsayılan mikroservis adresi.
  /// USB üzerinden `adb reverse tcp:8000 tcp:8000` ile gerçek cihaz doğrudan 127.0.0.1:8000'e bağlanır.
  /// Kablosuz (Wi-Fi) testte uygulama içinden bilgisayarın yerel IP adresi girilebilir.
  static const String defaultBaseUrl = 'http://127.0.0.1:8000';

  /// Kotlin native katmanı ile haberleşen MethodChannel adı.
  static const String methodChannelName = 'com.screentimeguard/native';

  /// Aynı uyarı durumunun tekrar bildirim/overlay göstermesi için beklenecek minimum süre (dakika).
  static const int alertCooldownMinutes = 15;

  // SharedPreferences anahtarları
  static const String keyDeviceToken = 'device_token';
  static const String keyDeviceId = 'device_id';
  static const String keyDeviceName = 'device_name';
  static const String keyApiBaseUrl = 'api_base_url';
  static const String keyCachedRule = 'cached_rule_json';
  static const String keyOfflineUsageQueue = 'offline_usage_queue_json';
  static const String keyLastAlertState = 'last_alert_state';
  static const String keyLastAlertEpochMs = 'last_alert_epoch_ms';
}
