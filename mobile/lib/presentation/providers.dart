import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api_client.dart';
import '../core/constants.dart';
import '../data/local_store.dart';
import '../data/rule_repository.dart';
import '../data/usage_repository.dart';
import '../domain/rule.dart';
import '../domain/rule_evaluator.dart';
import '../domain/usage_record.dart';
import '../platform/usage_channel.dart';

/// main() içinde başlatılan SharedPreferences örneğini sağlayan provider.
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('SharedPreferences main() içinde override edilmelidir.');
});

final localStoreProvider = Provider<LocalStore>((ref) {
  return LocalStore(ref.watch(sharedPreferencesProvider));
});

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(ref.watch(localStoreProvider));
});

final ruleRepositoryProvider = Provider<RuleRepository>((ref) {
  return RuleRepository(
    apiClient: ref.watch(apiClientProvider),
    localStore: ref.watch(localStoreProvider),
  );
});

final usageRepositoryProvider = Provider<UsageRepository>((ref) {
  return UsageRepository(
    apiClient: ref.watch(apiClientProvider),
    localStore: ref.watch(localStoreProvider),
    ruleRepository: ref.watch(ruleRepositoryProvider),
  );
});

final usageChannelProvider = Provider<UsageChannel>((ref) {
  return UsageChannel();
});

const _ruleEvaluator = RuleEvaluator();

/// Tüm ekranların ihtiyaç duyduğu birleşik uygulama durumu.
class AppState {
  final bool isLoading;
  final bool isServerReachable;
  final Rule rule;
  final UsageRecord todayUsage;
  final EvaluationResult evaluation;
  final UsageHistory history;
  final PermissionStatusSnapshot permissions;
  final int pendingOfflineCount;
  final String? statusBannerMessage;

  const AppState({
    required this.isLoading,
    required this.isServerReachable,
    required this.rule,
    required this.todayUsage,
    required this.evaluation,
    required this.history,
    required this.permissions,
    required this.pendingOfflineCount,
    this.statusBannerMessage,
  });

  factory AppState.initial(Rule cachedRule, int pendingCount) {
    final today = UsageRecord(
      date: UsageRecord.formatDate(DateTime.now()),
      totalMinutes: 0,
      topApps: const [],
    );
    final eval = _ruleEvaluator.evaluate(
      rule: cachedRule,
      usedMinutes: 0,
      now: DateTime.now(),
    );
    return AppState(
      isLoading: true,
      isServerReachable: false,
      rule: cachedRule,
      todayUsage: today,
      evaluation: eval,
      history: const UsageHistory(days: 7, averageMinutes: 0, items: []),
      permissions: const PermissionStatusSnapshot(),
      pendingOfflineCount: pendingCount,
    );
  }

  AppState copyWith({
    bool? isLoading,
    bool? isServerReachable,
    Rule? rule,
    UsageRecord? todayUsage,
    EvaluationResult? evaluation,
    UsageHistory? history,
    PermissionStatusSnapshot? permissions,
    int? pendingOfflineCount,
    String? statusBannerMessage,
  }) {
    return AppState(
      isLoading: isLoading ?? this.isLoading,
      isServerReachable: isServerReachable ?? this.isServerReachable,
      rule: rule ?? this.rule,
      todayUsage: todayUsage ?? this.todayUsage,
      evaluation: evaluation ?? this.evaluation,
      history: history ?? this.history,
      permissions: permissions ?? this.permissions,
      pendingOfflineCount: pendingOfflineCount ?? this.pendingOfflineCount,
      statusBannerMessage: statusBannerMessage,
    );
  }
}

/// Uygulama durumunu, periyodik senkronizasyonu ve kural değerlendirmesini yöneten Riverpod Notifier.
class AppController extends StateNotifier<AppState> {
  final LocalStore _localStore;
  final ApiClient _apiClient;
  final RuleRepository _ruleRepository;
  final UsageRepository _usageRepository;
  final UsageChannel _usageChannel;
  Timer? _syncTimer;

  AppController({
    required LocalStore localStore,
    required ApiClient apiClient,
    required RuleRepository ruleRepository,
    required UsageRepository usageRepository,
    required UsageChannel usageChannel,
  })  : _localStore = localStore,
        _apiClient = apiClient,
        _ruleRepository = ruleRepository,
        _usageRepository = usageRepository,
        _usageChannel = usageChannel,
        super(
          AppState.initial(
            localStore.getCachedRule(),
            usageRepository.pendingQueueCount,
          ),
        ) {
    // Kotlin MonitorService 60 saniyede bir kullanım verisi gönderdiğinde dinle
    _usageChannel.setOnPeriodicUsageUpdate(_onNativeUsageTick);

    // Her 15 dakikada bir kullanım verisini mikroservise senkronize et
    _syncTimer = Timer.periodic(
      const Duration(minutes: 15),
      (_) => syncNow(),
    );

    initialize();
  }

  /// İlk açılışta izinleri, cihaz kaydını, kuralı, bugünkü kullanımı ve geçmişi yükler.
  Future<void> initialize() async {
    state = state.copyWith(isLoading: true);

    final perms = await _usageChannel.checkPermissions();
    final today = await _usageChannel.getTodayUsage();
    final healthy = await _apiClient.checkHealth();
    final rule = await _ruleRepository.loadRule();

    final eval = _ruleEvaluator.evaluate(
      rule: rule,
      usedMinutes: today.totalMinutes,
      now: DateTime.now(),
    );

    // Bugünkü kullanım verisini senkronize etmeyi dene ve 7 günlük geçmişi çek
    await _usageRepository.syncUsageRecord(today);
    final history = await _usageRepository.fetchHistory(days: 7);

    state = state.copyWith(
      isLoading: false,
      isServerReachable: healthy,
      permissions: perms,
      rule: rule,
      todayUsage: today,
      evaluation: eval,
      history: history,
      pendingOfflineCount: _usageRepository.pendingQueueCount,
    );

    await _maybeTriggerAlert(eval);
  }

  /// Native MonitorService'den her 60 saniyede gelen kullanım güncellemelerini işler.
  Future<void> _onNativeUsageTick(UsageRecord latestToday) async {
    final eval = _ruleEvaluator.evaluate(
      rule: state.rule,
      usedMinutes: latestToday.totalMinutes,
      now: DateTime.now(),
    );
    state = state.copyWith(
      todayUsage: latestToday,
      evaluation: eval,
    );
    await _maybeTriggerAlert(eval);
  }

  /// Kullanımı Kotlin'den tekrar okur ve değerlendirmeyi yeniler.
  Future<void> refreshTodayUsage() async {
    final perms = await _usageChannel.checkPermissions();
    final today = await _usageChannel.getTodayUsage();
    final eval = _ruleEvaluator.evaluate(
      rule: state.rule,
      usedMinutes: today.totalMinutes,
      now: DateTime.now(),
    );
    state = state.copyWith(
      permissions: perms,
      todayUsage: today,
      evaluation: eval,
    );
    await _maybeTriggerAlert(eval);
  }

  /// Kuralı günceller (önce yerel önbellek, sonra PUT /v1/rules).
  Future<bool> updateRule(Rule newRule) async {
    final result = await _ruleRepository.saveRule(newRule);
    final eval = _ruleEvaluator.evaluate(
      rule: result.rule,
      usedMinutes: state.todayUsage.totalMinutes,
      now: DateTime.now(),
    );
    state = state.copyWith(
      rule: result.rule,
      evaluation: eval,
      isServerReachable: result.syncedWithServer,
      statusBannerMessage: result.syncedWithServer
          ? 'Kural sunucuya ve cihaza kaydedildi.'
          : 'Çevrimdışı mod: Kural cihaza kaydedildi.',
    );
    await _maybeTriggerAlert(eval);
    return result.syncedWithServer;
  }

  /// Bugünkü kullanımı manuel veya periyodik olarak POST /v1/usage ile senkronize eder.
  Future<bool> syncNow() async {
    final today = await _usageChannel.getTodayUsage();
    final synced = await _usageRepository.syncUsageRecord(today);
    final history = await _usageRepository.fetchHistory(days: 7);
    final eval = _ruleEvaluator.evaluate(
      rule: state.rule,
      usedMinutes: today.totalMinutes,
      now: DateTime.now(),
    );

    state = state.copyWith(
      todayUsage: today,
      evaluation: eval,
      history: history,
      isServerReachable: synced,
      pendingOfflineCount: _usageRepository.pendingQueueCount,
      statusBannerMessage: synced
          ? 'Senkronizasyon başarılı.'
          : 'Sunucuya ulaşılamadı; veri yerel kuyruğa eklendi.',
    );
    return synced;
  }

  /// Sunucu IP/URL adresini günceller ve yeniden bağlanmayı dener.
  Future<void> updateServerUrl(String newUrl) async {
    await _localStore.setApiBaseUrl(newUrl);
    await initialize();
  }

  /// İzin durumlarını yeniler.
  Future<void> refreshPermissions() async {
    final perms = await _usageChannel.checkPermissions();
    state = state.copyWith(permissions: perms);
  }

  /// Foreground MonitorService'i başlatır veya durdurur.
  Future<void> toggleMonitorService(bool enable) async {
    if (enable) {
      await _usageChannel.startMonitorService();
    } else {
      await _usageChannel.stopMonitorService();
    }
    await refreshPermissions();
  }

  /// Aynı uyarının üst üste çıkmaması için son uyarı zamanını kontrol ederek bildirim/overlay gösterir.
  Future<void> _maybeTriggerAlert(EvaluationResult eval) async {
    if (!eval.state.shouldAlert) return;

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final lastState = _localStore.getLastAlertState();
    final lastEpochMs = _localStore.getLastAlertEpochMs() ?? 0;
    const cooldownMs = AppConstants.alertCooldownMinutes * 60 * 1000;

    final isSameState = lastState == eval.state.code;
    final withinCooldown = (nowMs - lastEpochMs) < cooldownMs;

    if (isSameState && withinCooldown) {
      return;
    }

    await _localStore.saveLastAlert(
      stateCode: eval.state.code,
      epochMs: nowMs,
    );

    await _usageChannel.triggerUserAlert(
      title: 'ScreenTime Guard: ${eval.state.title}',
      message: eval.message,
      mode: state.rule.mode.value,
    );
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    super.dispose();
  }
}

final appControllerProvider =
    StateNotifierProvider<AppController, AppState>((ref) {
  return AppController(
    localStore: ref.watch(localStoreProvider),
    apiClient: ref.watch(apiClientProvider),
    ruleRepository: ref.watch(ruleRepositoryProvider),
    usageRepository: ref.watch(usageRepositoryProvider),
    usageChannel: ref.watch(usageChannelProvider),
  );
});
