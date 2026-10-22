import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';

/// Android sistem izinlerini (Usage Access, Overlay, Bildirim) ve
/// arka plan izleme servisini (MonitorService) yöneten ekran.
class PermissionsScreen extends ConsumerWidget {
  const PermissionsScreen({super.key});

  Widget _buildPermissionCard({
    required String title,
    required String description,
    required bool granted,
    required VoidCallback onRequest,
    required String buttonText,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  granted ? Icons.verified_rounded : Icons.error_outline_rounded,
                  color: granted ? Colors.green : Colors.orange.shade800,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Chip(
                  label: Text(granted ? 'Verildi' : 'Gerekli'),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(description, style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton(
                onPressed: onRequest,
                child: Text(buttonText),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appControllerProvider);
    final notifier = ref.read(appControllerProvider.notifier);
    final channel = ref.read(usageChannelProvider);
    final perms = state.permissions;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Gerekli Android İzinleri',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            TextButton.icon(
              onPressed: () => notifier.refreshPermissions(),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Durumu Kontrol Et'),
            ),
          ],
        ),
        const SizedBox(height: 8),

        _buildPermissionCard(
          title: '1. Kullanım Verisi Erişimi (Usage Access)',
          description:
              'UsageStatsManager ile günlük toplam ekran süresini ve en çok kullanılan uygulamaları okuyabilmek için zorunludur (PACKAGE_USAGE_STATS).',
          granted: perms.hasUsageStatsPermission,
          buttonText: 'Ayarları Aç',
          onRequest: () async {
            await channel.openUsageAccessSettings();
          },
        ),

        _buildPermissionCard(
          title: '2. Ekran Üstü Gösterim (Overlay)',
          description:
              'Limit aşıldığında veya kesme saatinde diğer uygulamaların üzerinde uyarı penceresi gösterebilmek için kullanılır (SYSTEM_ALERT_WINDOW).',
          granted: perms.hasOverlayPermission,
          buttonText: 'Overlay İznini Aç',
          onRequest: () async {
            await channel.openOverlaySettings();
          },
        ),

        _buildPermissionCard(
          title: '3. Bildirim İzni (Android 13+)',
          description:
              'Limitin %80\'ine ulaşıldığında ve arka plan izleme servisi çalışırken bildirim gösterebilmek için gereklidir (POST_NOTIFICATIONS).',
          granted: perms.hasNotificationPermission,
          buttonText: 'İzin İste',
          onRequest: () async {
            await channel.requestNotificationPermission();
            await notifier.refreshPermissions();
          },
        ),

        const SizedBox(height: 12),
        Card(
          child: SwitchListTile(
            title: const Text(
              'Arka Plan İzleme Servisi (MonitorService)',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: const Text(
              'Foreground Service olarak 60 saniyede bir ekran süresini kontrol eder.',
            ),
            value: perms.isMonitoringActive,
            onChanged: (val) => notifier.toggleMonitorService(val),
          ),
        ),
      ],
    );
  }
}
