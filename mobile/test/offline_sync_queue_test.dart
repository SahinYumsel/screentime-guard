import 'package:flutter_test/flutter_test.dart';
import 'package:screentime_guard/data/local_store.dart';
import 'package:screentime_guard/domain/usage_record.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('Offline senkronizasyon kuyruğu (LocalStore) testleri', () {
    test('Aynı gün için kuyruğa eklenen kullanım verisi idempotent olarak üzerine yazılmalı', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = LocalStore(prefs);

      const firstRecord = UsageRecord(
        date: '2026-10-22',
        totalMinutes: 60,
        topApps: [AppUsageItem(packageName: 'com.instagram.android', minutes: 35)],
      );

      const updatedRecord = UsageRecord(
        date: '2026-10-22',
        totalMinutes: 125,
        topApps: [AppUsageItem(packageName: 'com.instagram.android', minutes: 70)],
      );

      await store.enqueueOfflineUsage(firstRecord);
      await store.enqueueOfflineUsage(updatedRecord);

      final queue = store.getOfflineUsageQueue();
      expect(queue.length, 1);
      expect(queue.first.totalMinutes, 125);
      expect(queue.first.topApps.first.minutes, 70);

      await store.removeOfflineUsageByDate('2026-10-22');
      expect(store.getOfflineUsageQueue(), isEmpty);
    });
  });
}
