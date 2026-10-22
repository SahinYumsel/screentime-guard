import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/rule_evaluator.dart';
import '../providers.dart';

/// Bugünkü kullanım süresini, aktif kural değerlendirme durumunu ve
/// en çok kullanılan uygulamaları gösteren ana ekran.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  Color _stateColor(RuleCheckState state, ColorScheme scheme) {
    switch (state) {
      case RuleCheckState.ok:
        return Colors.teal;
      case RuleCheckState.warn80:
        return Colors.orange.shade800;
      case RuleCheckState.limitExceeded:
        return scheme.error;
      case RuleCheckState.inCutoffWindow:
        return Colors.deepPurple;
    }
  }

  IconData _stateIcon(RuleCheckState state) {
    switch (state) {
      case RuleCheckState.ok:
        return Icons.check_circle_outline;
      case RuleCheckState.warn80:
        return Icons.warning_amber_rounded;
      case RuleCheckState.limitExceeded:
        return Icons.timer_off_outlined;
      case RuleCheckState.inCutoffWindow:
        return Icons.bedtime_outlined;
    }
  }

  Future<void> _showServerConfigDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final store = ref.read(localStoreProvider);
    final controller = TextEditingController(text: store.getApiBaseUrl());

    final savedUrl = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mikroservis Bağlantı Adresi'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Gerçek cihazda test ederken bilgisayarınızın aynı Wi-Fi ağındaki IP adresini girin (örn. http://192.168.1.45:8000).',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'API Base URL',
                border: OutlineInputBorder(),
                hintText: 'http://192.168.1.45:8000',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('İptal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );

    if (savedUrl != null && savedUrl.isNotEmpty) {
      await ref.read(appControllerProvider.notifier).updateServerUrl(savedUrl);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appControllerProvider);
    final notifier = ref.read(appControllerProvider.notifier);
    final colorScheme = Theme.of(context).colorScheme;
    final eval = state.evaluation;
    final badgeColor = _stateColor(eval.state, colorScheme);

    return RefreshIndicator(
      onRefresh: () => notifier.syncNow(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Sunucu ve Offline Kuyruk Durum Çubuğu
          Card(
            elevation: 0,
            color: state.isServerReachable
                ? Colors.green.withValues(alpha: 0.1)
                : Colors.amber.withValues(alpha: 0.15),
            child: ListTile(
              leading: Icon(
                state.isServerReachable ? Icons.cloud_done : Icons.cloud_off,
                color: state.isServerReachable
                    ? Colors.green.shade700
                    : Colors.amber.shade900,
              ),
              title: Text(
                state.isServerReachable
                    ? 'Mikroservis Bağlı'
                    : 'Çevrimdışı Mod (Offline-First)',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                state.pendingOfflineCount > 0
                    ? 'Kuyrukta bekleyen ${state.pendingOfflineCount} kayıt var'
                    : 'Tüm veriler güncel',
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Sunucu Adresini Düzenle',
                    icon: const Icon(Icons.settings_ethernet),
                    onPressed: () => _showServerConfigDialog(context, ref),
                  ),
                  IconButton(
                    tooltip: 'Şimdi Senkronize Et',
                    icon: const Icon(Icons.sync),
                    onPressed: () async {
                      final ok = await notifier.syncNow();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              ok
                                  ? 'Veriler mikroservise gönderildi.'
                                  : 'Çevrimdışı: Veri yerel kuyruğa kaydedildi.',
                            ),
                          ),
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Bugünkü Toplam Süre ve Limit Kartı
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(_stateIcon(eval.state), color: badgeColor, size: 28),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          eval.state.title,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: badgeColor,
                          ),
                        ),
                      ),
                      Chip(
                        label: Text(state.rule.mode.label),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        '${eval.usedMinutes}',
                        style: const TextStyle(
                          fontSize: 44,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '/ ${eval.dailyLimitMin} dk günlük limit',
                        style: TextStyle(
                          fontSize: 16,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: eval.progressRatio,
                      minHeight: 12,
                      color: badgeColor,
                      backgroundColor: colorScheme.surfaceContainerHighest,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    eval.message,
                    style: const TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Kesme Saati: ${state.rule.cutoffStart} - ${state.rule.cutoffEnd}',
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Bugün En Çok Kullanılan Uygulamalar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Bugün En Çok Kullanılanlar',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              TextButton.icon(
                onPressed: () => notifier.refreshTodayUsage(),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Süreyi Yenile'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (state.todayUsage.topApps.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  'Henüz uygulama kullanım verisi okunmadı veya Usage Access izni verilmedi.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          else
            ...state.todayUsage.topApps.map(
              (app) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    child: Text(
                      app.shortName.substring(0, 1).toUpperCase(),
                    ),
                  ),
                  title: Text(app.shortName),
                  subtitle: Text(
                    app.packageName,
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: Text(
                    '${app.minutes} dk',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
