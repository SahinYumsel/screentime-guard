import 'package:flutter_test/flutter_test.dart';
import 'package:screentime_guard/domain/rule.dart';
import 'package:screentime_guard/domain/rule_evaluator.dart';

void main() {
  const evaluator = RuleEvaluator();
  final baseRule = Rule(
    dailyLimitMin: 100,
    cutoffStart: '23:00',
    cutoffEnd: '06:00',
    mode: RuleMode.notify,
  );

  group('RuleEvaluator birim testleri', () {
    test('Gün içi normal kullanımda ok durumu dönmeli', () {
      final result = evaluator.evaluate(
        rule: baseRule,
        usedMinutes: 45,
        now: DateTime(2026, 10, 22, 14, 30), // 14:30
      );

      expect(result.state, RuleCheckState.ok);
      expect(result.remainingMinutes, 55);
    });

    test('Günlük limitin %80\'ine ulaşıldığında warn_80 durumu dönmeli', () {
      final result = evaluator.evaluate(
        rule: baseRule,
        usedMinutes: 80,
        now: DateTime(2026, 10, 22, 16, 0), // 16:00
      );

      expect(result.state, RuleCheckState.warn80);
      expect(result.remainingMinutes, 20);
    });

    test('Günlük limit aşıldığında limit_exceeded durumu dönmeli', () {
      final result = evaluator.evaluate(
        rule: baseRule,
        usedMinutes: 115,
        now: DateTime(2026, 10, 22, 19, 15), // 19:15
      );

      expect(result.state, RuleCheckState.limitExceeded);
      expect(result.remainingMinutes, 0);
    });

    test('Gece yarısını aşan kesme saatinde (23:00-06:00) 23:30 ve 02:15 için in_cutoff_window dönmeli', () {
      // Gece yarısından önce (23:30)
      final beforeMidnight = evaluator.evaluate(
        rule: baseRule,
        usedMinutes: 20,
        now: DateTime(2026, 10, 22, 23, 30),
      );
      expect(beforeMidnight.state, RuleCheckState.inCutoffWindow);

      // Gece yarısından sonra (02:15)
      final afterMidnight = evaluator.evaluate(
        rule: baseRule,
        usedMinutes: 5,
        now: DateTime(2026, 10, 23, 2, 15),
      );
      expect(afterMidnight.state, RuleCheckState.inCutoffWindow);

      // Bitiş sınırında (06:00) kesme penceresi bitmiş olmalı
      final atSixAm = evaluator.evaluate(
        rule: baseRule,
        usedMinutes: 5,
        now: DateTime(2026, 10, 23, 6, 0),
      );
      expect(atSixAm.state, RuleCheckState.ok);
    });

    test('Aynı gün içindeki kesme saati aralığı (01:00-05:00) doğru hesaplanmalı', () {
      final sameDayRule = baseRule.copyWith(
        cutoffStart: '01:00',
        cutoffEnd: '05:00',
      );

      final inside = evaluator.evaluate(
        rule: sameDayRule,
        usedMinutes: 10,
        now: DateTime(2026, 10, 22, 3, 0),
      );
      expect(inside.state, RuleCheckState.inCutoffWindow);

      final outside = evaluator.evaluate(
        rule: sameDayRule,
        usedMinutes: 10,
        now: DateTime(2026, 10, 22, 23, 30),
      );
      expect(outside.state, RuleCheckState.ok);
    });
  });
}
