import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';

/// GET /v1/usage?days=7 verisini kullanarak haftalık kullanım ortalamasını
/// ve gün bazlı kullanım geçmişini gösteren ekran.
class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appControllerProvider);
    final notifier = ref.read(appControllerProvider.notifier);
    final history = state.history;
    final limitMin = state.rule.dailyLimitMin;
    final scheme = Theme.of(context).colorScheme;

    return RefreshIndicator(
      onRefresh: () => notifier.syncNow(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 7 Günlük Ortalama Kartı
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: scheme.primaryContainer,
                    child: Icon(
                      Icons.bar_chart_rounded,
                      color: scheme.onPrimaryContainer,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Son ${history.days} Günlük Ortalama',
                          style: TextStyle(
                            fontSize: 14,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${history.averageMinutes.toStringAsFixed(1)} dk / gün',
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          const Text(
            'Günlük Kayıtlar',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),

          if (history.items.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Henüz geçmiş kullanım kaydı yok. Ana ekrandan "Senkronize Et" butonuna basarak bugünkü veriyi gönderebilirsiniz.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          else
            ...history.items.map((item) {
              final exceeded = item.totalMinutes >= limitMin;
              final ratio = limitMin > 0
                  ? (item.totalMinutes / limitMin).clamp(0.0, 1.0)
                  : 1.0;

              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            item.date,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          Text(
                            '${item.totalMinutes} dk',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: exceeded ? scheme.error : Colors.teal,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: ratio,
                          minHeight: 8,
                          color: exceeded ? scheme.error : Colors.teal,
                        ),
                      ),
                      if (item.topApps.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: item.topApps.take(3).map((app) {
                            return Chip(
                              label: Text(
                                '${app.shortName}: ${app.minutes} dk',
                                style: const TextStyle(fontSize: 12),
                              ),
                              visualDensity: VisualDensity.compact,
                            );
                          }).toList(),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}
