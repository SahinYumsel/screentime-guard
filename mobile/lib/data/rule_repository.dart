import '../core/api_client.dart';
import '../domain/rule.dart';
import 'local_store.dart';

/// Cihaz kaydını ve kural (Rule) senkronizasyonunu yöneten repository.
/// Offline-first prensibiyle çalışır: internet yoksa yerel önbellekteki kuralı döndürür.
class RuleRepository {
  final ApiClient _apiClient;
  final LocalStore _localStore;

  const RuleRepository({
    required ApiClient apiClient,
    required LocalStore localStore,
  })  : _apiClient = apiClient,
        _localStore = localStore;

  /// Cihaz henüz kayıtlı değilse POST /v1/devices çağırarak token alır ve saklar.
  Future<bool> ensureDeviceRegistered({String? deviceName}) async {
    final existingToken = _localStore.getDeviceToken();
    if (existingToken != null && existingToken.isNotEmpty) {
      return true;
    }
    try {
      final name = deviceName ?? _localStore.getDeviceName();
      final data = await _apiClient.registerDevice(name: name);
      await _localStore.saveDeviceCredentials(
        deviceId: data['device_id'].toString(),
        token: data['token'].toString(),
        name: name,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Sunucudan güncel kuralı çeker ve yerel önbelleğe yazar;
  /// bağlantı yoksa yerel önbellekteki (veya varsayılan) kuralı döndürür.
  Future<Rule> loadRule() async {
    try {
      await ensureDeviceRegistered();
      final remoteRule = await _apiClient.fetchRule();
      await _localStore.saveCachedRule(remoteRule);
      return remoteRule;
    } catch (_) {
      return _localStore.getCachedRule();
    }
  }

  /// Kuralı önce yerelde günceller (offline-first), ardından sunucuya PUT /v1/rules gönderir.
  /// Sunucuya ulaşılamazsa yerel kural yine de geçerli olur ve `syncedWithServer = false` döner.
  Future<({Rule rule, bool syncedWithServer})> saveRule(Rule updatedRule) async {
    await _localStore.saveCachedRule(updatedRule);
    try {
      await ensureDeviceRegistered();
      final remote = await _apiClient.updateRule(updatedRule);
      await _localStore.saveCachedRule(remote);
      return (rule: remote, syncedWithServer: true);
    } catch (_) {
      return (rule: updatedRule, syncedWithServer: false);
    }
  }
}
