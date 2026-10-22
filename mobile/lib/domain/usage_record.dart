/// Gün içinde en çok kullanılan tekil bir uygulamanın süre bilgisi.
class AppUsageItem {
  final String packageName;
  final int minutes;

  const AppUsageItem({
    required this.packageName,
    required this.minutes,
  });

  factory AppUsageItem.fromJson(Map<String, dynamic> json) {
    return AppUsageItem(
      packageName: (json['package'] ?? '').toString(),
      minutes: (json['minutes'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'package': packageName,
      'minutes': minutes,
    };
  }

  /// Paket adından okunabilir kısa ad türetir (örn. com.instagram.android -> instagram).
  String get shortName {
    final parts = packageName.split('.');
    if (parts.length >= 2) {
      final candidate = parts.last == 'android' && parts.length >= 3
          ? parts[parts.length - 2]
          : parts.last;
      return candidate.isEmpty ? packageName : candidate;
    }
    return packageName;
  }
}

/// Bir güne ait toplam kullanım süresi ve uygulama dağılımı kaydı.
class UsageRecord {
  final String date; // YYYY-MM-DD
  final int totalMinutes;
  final List<AppUsageItem> topApps;
  final DateTime? syncedAt;

  const UsageRecord({
    required this.date,
    required this.totalMinutes,
    required this.topApps,
    this.syncedAt,
  });

  factory UsageRecord.fromJson(Map<String, dynamic> json) {
    final rawApps = json['top_apps'];
    final apps = <AppUsageItem>[];
    if (rawApps is List) {
      for (final item in rawApps) {
        if (item is Map) {
          apps.add(AppUsageItem.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }

    return UsageRecord(
      date: (json['date'] ?? '').toString(),
      totalMinutes: (json['total_minutes'] as num?)?.toInt() ?? 0,
      topApps: apps,
      syncedAt: json['synced_at'] != null
          ? DateTime.tryParse(json['synced_at'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'date': date,
      'total_minutes': totalMinutes,
      'top_apps': topApps.map((e) => e.toJson()).toList(),
    };
  }

  /// Bugünün tarihini YYYY-MM-DD formatında döndürür.
  static String formatDate(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}

/// GET /v1/usage?days=7 yanıt modeli (geçmiş kayıtlar + ortalama süre).
class UsageHistory {
  final int days;
  final double averageMinutes;
  final List<UsageRecord> items;

  const UsageHistory({
    required this.days,
    required this.averageMinutes,
    required this.items,
  });

  factory UsageHistory.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    final parsedItems = <UsageRecord>[];
    if (rawItems is List) {
      for (final item in rawItems) {
        if (item is Map) {
          parsedItems.add(
            UsageRecord.fromJson(Map<String, dynamic>.from(item)),
          );
        }
      }
    }
    return UsageHistory(
      days: (json['days'] as num?)?.toInt() ?? 7,
      averageMinutes: (json['average_minutes'] as num?)?.toDouble() ?? 0.0,
      items: parsedItems,
    );
  }
}
