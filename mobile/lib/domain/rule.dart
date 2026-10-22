/// Uyarı gösterim modu: Bildirim (notify) veya Ekran Üstü Uyarı (overlay).
enum RuleMode {
  notify('notify', 'Bildirim'),
  overlay('overlay', 'Ekran Üstü Uyarı (Overlay)');

  final String value;
  final String label;
  const RuleMode(this.value, this.label);

  static RuleMode fromString(String? raw) {
    return RuleMode.values.firstWhere(
      (m) => m.value == raw,
      orElse: () => RuleMode.notify,
    );
  }
}

/// Cihazın ekran süresi limiti ve kesme saati (cutoff) kuralı.
class Rule {
  final String? deviceId;
  final int dailyLimitMin;
  final String cutoffStart; // HH:MM (örn. 23:00)
  final String cutoffEnd;   // HH:MM (örn. 06:00)
  final RuleMode mode;
  final DateTime? updatedAt;

  const Rule({
    this.deviceId,
    required this.dailyLimitMin,
    required this.cutoffStart,
    required this.cutoffEnd,
    required this.mode,
    this.updatedAt,
  });

  /// İnternet bağlantısı olmadığında bile çalışacak varsayılan kural.
  factory Rule.defaults() {
    return const Rule(
      dailyLimitMin: 120,
      cutoffStart: '23:00',
      cutoffEnd: '06:00',
      mode: RuleMode.notify,
    );
  }

  factory Rule.fromJson(Map<String, dynamic> json) {
    return Rule(
      deviceId: json['device_id']?.toString(),
      dailyLimitMin: (json['daily_limit_min'] as num?)?.toInt() ?? 120,
      cutoffStart: (json['cutoff_start'] ?? '23:00').toString(),
      cutoffEnd: (json['cutoff_end'] ?? '06:00').toString(),
      mode: RuleMode.fromString(json['mode']?.toString()),
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (deviceId != null) 'device_id': deviceId,
      'daily_limit_min': dailyLimitMin,
      'cutoff_start': cutoffStart,
      'cutoff_end': cutoffEnd,
      'mode': mode.value,
      if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
    };
  }

  /// PUT /v1/rules gövdesi için JSON.
  Map<String, dynamic> toUpdateJson() {
    return {
      'daily_limit_min': dailyLimitMin,
      'cutoff_start': cutoffStart,
      'cutoff_end': cutoffEnd,
      'mode': mode.value,
    };
  }

  Rule copyWith({
    String? deviceId,
    int? dailyLimitMin,
    String? cutoffStart,
    String? cutoffEnd,
    RuleMode? mode,
    DateTime? updatedAt,
  }) {
    return Rule(
      deviceId: deviceId ?? this.deviceId,
      dailyLimitMin: dailyLimitMin ?? this.dailyLimitMin,
      cutoffStart: cutoffStart ?? this.cutoffStart,
      cutoffEnd: cutoffEnd ?? this.cutoffEnd,
      mode: mode ?? this.mode,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
