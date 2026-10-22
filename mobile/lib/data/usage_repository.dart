import '../core/api_client.dart';
import '../domain/usage_record.dart';
import 'local_store.dart';
import 'rule_repository.dart';

/// Günlük kullanım verisinin sunucuya gönderilmesini, çevrimdışı kuyruğa
/// alınmasını ve haftalık geçmişin çekilmesini yöneten repository.
class UsageRepository {
  final ApiClient _apiClient;
  final LocalStore _localStore;
  final RuleRepository _ruleRepository;

  const UsageRepository({
    required ApiClient apiClient,
    required LocalStore localStore,
    required RuleRepository ruleRepository,
  })  : _apiClient = apiClient,
        _localStore = localStore,
        _ruleRepository = ruleRepository;

  /// Günlük kullanımı sunucuya gönderir (POST /v1/usage).
  /// Başarısız olursa yerel çevrimdışı kuyruğa yazar; başarılı olursa bekleyen kuyruğu da eritir.
  Future<bool> syncUsageRecord(UsageRecord record) async {
    try {
      final registered = await _ruleRepository.ensureDeviceRegistered();
      if (!registered) {
        await _localStore.enqueueOfflineUsage(record);
        return false;
      }

      await _apiClient.postUsage(record);
      await _localStore.removeOfflineUsageByDate(record.date);

      // Bağlantı gelmişken kuyrukta bekleyen eski kayıtları da gönder
      await flushOfflineQueue();
      return true;
    } catch (_) {
      await _localStore.enqueueOfflineUsage(record);
      return false;
    }
  }

  /// Yerel kuyrukta bekleyen çevrimdışı kullanım kayıtlarını sırayla sunucuya gönderir.
  Future<int> flushOfflineQueue() async {
    final queue = _localStore.getOfflineUsageQueue();
    if (queue.isEmpty) return 0;

    int flushedCount = 0;
    for (final item in queue) {
      try {
        await _apiClient.postUsage(item);
        await _localStore.removeOfflineUsageByDate(item.date);
        flushedCount++;
      } catch (_) {
        // Bağlantı tekrar koptuysa kalanları sonraki denemeye bırak
        break;
      }
    }
    return flushedCount;
  }

  /// GET /v1/usage?days=7 ile geçmiş kayıtları getirir.
  /// Çevrimdışı durumda yerel kuyruktaki kayıtları kullanarak anlamlı bir görünüm üretir.
  Future<UsageHistory> fetchHistory({int days = 7}) async {
    try {
      await _ruleRepository.ensureDeviceRegistered();
      await flushOfflineQueue();
      return await _apiClient.fetchUsageHistory(days: days);
    } catch (_) {
      final localItems = _localStore.getOfflineUsageQueue();
      final avg = localItems.isEmpty
          ? 0.0
          : localItems.fold<int>(0, (s, r) => s + r.totalMinutes) /
              localItems.length;
      return UsageHistory(
        days: days,
        averageMinutes: double.parse(avg.toStringAsFixed(1)),
        items: localItems,
      );
    }
  }

  int get pendingQueueCount => _localStore.getOfflineUsageQueue().length;
}
