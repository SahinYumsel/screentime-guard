import 'rule.dart';

/// Kural değerlendirme sonucunda oluşan durumlar (architecture.md Bölüm 7).
enum RuleCheckState {
  ok('ok', 'Normal'),
  warn80('warn_80', '%80 Limit Uyarısı'),
  limitExceeded('limit_exceeded', 'Günlük Limit Aşıldı'),
  inCutoffWindow('in_cutoff_window', 'Kesme Saati (Gece Modu)');

  final String code;
  final String title;
  const RuleCheckState(this.code, this.title);

  bool get shouldAlert => this != RuleCheckState.ok;
}

/// RuleEvaluator tarafından döndürülen ayrıntılı değerlendirme sonucu.
class EvaluationResult {
  final RuleCheckState state;
  final int usedMinutes;
  final int dailyLimitMin;
  final String message;

  const EvaluationResult({
    required this.state,
    required this.usedMinutes,
    required this.dailyLimitMin,
    required this.message,
  });

  int get remainingMinutes {
    final diff = dailyLimitMin - usedMinutes;
    return diff < 0 ? 0 : diff;
  }

  double get progressRatio {
    if (dailyLimitMin <= 0) return 1.0;
    final ratio = usedMinutes / dailyLimitMin;
    return ratio > 1.0 ? 1.0 : ratio;
  }
}

/// Offline-first kural değerlendirici.
/// Günlük limitin %80'ine ulaşılması, limit aşımı ve gece yarısını aşabilen
/// kesme saati aralığını (örn. 23:00 - 06:00) telefonda değerlendirir.
class RuleEvaluator {
  const RuleEvaluator();

  /// "HH:MM" formatındaki saati gece yarısından itibaren geçen dakikaya çevirir (0..1439).
  static int parseMinutesOfDay(String hhmm) {
    final parts = hhmm.trim().split(':');
    if (parts.length != 2) {
      throw FormatException('Geçersiz saat formatı: $hhmm');
    }
    final hour = int.parse(parts[0]);
    final minute = int.parse(parts[1]);
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
      throw FormatException('Saat aralığı dışında: $hhmm');
    }
    return hour * 60 + minute;
  }

  /// Verilen `now` zamanının `[cutoffStart, cutoffEnd)` aralığında olup olmadığını kontrol eder.
  /// Gece yarısını aşan aralıkları (örn. 23:00 - 06:00) doğru ele alır.
  static bool isInCutoffWindow({
    required DateTime now,
    required String cutoffStart,
    required String cutoffEnd,
  }) {
    final startMin = parseMinutesOfDay(cutoffStart);
    final endMin = parseMinutesOfDay(cutoffEnd);

    // Başlangıç ve bitiş aynıysa kesme penceresi devre dışı kabul edilir
    if (startMin == endMin) {
      return false;
    }

    final currentMin = now.hour * 60 + now.minute;

    if (startMin < endMin) {
      // Aynı gün içindeki aralık (örn. 01:00 - 05:00)
      return currentMin >= startMin && currentMin < endMin;
    } else {
      // Gece yarısını aşan aralık (örn. 23:00 - 06:00)
      // Saat 23:00'dan büyük/eşit VEYA sabah 06:00'dan küçükse kesme saatindedir.
      return currentMin >= startMin || currentMin < endMin;
    }
  }

  /// Bugünkü kullanım süresini (`usedMinutes`) ve şu anki saati (`now`) aktif kurala göre değerlendirir.
  EvaluationResult evaluate({
    required Rule rule,
    required int usedMinutes,
    required DateTime now,
  }) {
    final inCutoff = isInCutoffWindow(
      now: now,
      cutoffStart: rule.cutoffStart,
      cutoffEnd: rule.cutoffEnd,
    );

    if (inCutoff) {
      return EvaluationResult(
        state: RuleCheckState.inCutoffWindow,
        usedMinutes: usedMinutes,
        dailyLimitMin: rule.dailyLimitMin,
        message:
            'Kesme saati aralığındasınız (${rule.cutoffStart} - ${rule.cutoffEnd}). Dinlenme vakti!',
      );
    }

    if (usedMinutes >= rule.dailyLimitMin) {
      final extra = usedMinutes - rule.dailyLimitMin;
      return EvaluationResult(
        state: RuleCheckState.limitExceeded,
        usedMinutes: usedMinutes,
        dailyLimitMin: rule.dailyLimitMin,
        message:
            'Günlük ekran süresi limitiniz (${rule.dailyLimitMin} dk) doldu! (+$extra dk aşım)',
      );
    }

    final warnThreshold = (rule.dailyLimitMin * 0.8).ceil();
    if (usedMinutes >= warnThreshold) {
      final remaining = rule.dailyLimitMin - usedMinutes;
      return EvaluationResult(
        state: RuleCheckState.warn80,
        usedMinutes: usedMinutes,
        dailyLimitMin: rule.dailyLimitMin,
        message:
            'Günlük limitinizin %80\'ine ulaştınız. Kalan süre: $remaining dk.',
      );
    }

    final remaining = rule.dailyLimitMin - usedMinutes;
    return EvaluationResult(
      state: RuleCheckState.ok,
      usedMinutes: usedMinutes,
      dailyLimitMin: rule.dailyLimitMin,
      message: 'Kullanım normal seviyede. Kalan günlük hak: $remaining dk.',
    );
  }
}
