import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/rule.dart';
import '../providers.dart';

/// Günlük limit, kesme saati (cutoff) ve uyarı modunu (notify/overlay)
/// düzenleme ekranı. Değişiklikler hem yerel önbelleğe hem de PUT /v1/rules'a kaydedilir.
class RulesScreen extends ConsumerStatefulWidget {
  const RulesScreen({super.key});

  @override
  ConsumerState<RulesScreen> createState() => _RulesScreenState();
}

class _RulesScreenState extends ConsumerState<RulesScreen> {
  late int _dailyLimitMin;
  late String _cutoffStart;
  late String _cutoffEnd;
  late RuleMode _mode;
  bool _initializedFromState = false;
  bool _isSaving = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initializedFromState) {
      final currentRule = ref.read(appControllerProvider).rule;
      _dailyLimitMin = currentRule.dailyLimitMin;
      _cutoffStart = currentRule.cutoffStart;
      _cutoffEnd = currentRule.cutoffEnd;
      _mode = currentRule.mode;
      _initializedFromState = true;
    }
  }

  TimeOfDay _parseTime(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length == 2) {
      return TimeOfDay(
        hour: int.tryParse(parts[0]) ?? 23,
        minute: int.tryParse(parts[1]) ?? 0,
      );
    }
    return const TimeOfDay(hour: 23, minute: 0);
  }

  String _formatTime(TimeOfDay tod) {
    final h = tod.hour.toString().padLeft(2, '0');
    final m = tod.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  Future<void> _pickTime({required bool isStart}) async {
    final initial = _parseTime(isStart ? _cutoffStart : _cutoffEnd);
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _cutoffStart = _formatTime(picked);
        } else {
          _cutoffEnd = _formatTime(picked);
        }
      });
    }
  }

  Future<void> _saveRule() async {
    setState(() => _isSaving = true);
    final updated = Rule(
      dailyLimitMin: _dailyLimitMin,
      cutoffStart: _cutoffStart,
      cutoffEnd: _cutoffEnd,
      mode: _mode,
    );
    final synced =
        await ref.read(appControllerProvider.notifier).updateRule(updated);
    if (mounted) {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            synced
                ? 'Kural güncellendi ve mikroservise kaydedildi.'
                : 'Çevrimdışı mod: Kural yerel olarak kaydedildi.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Günlük Ekran Süresi Limiti',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Seçilen Limit: $_dailyLimitMin dakika (${(_dailyLimitMin / 60).toStringAsFixed(1)} saat)',
                  style: const TextStyle(fontSize: 15),
                ),
                Slider(
                  value: _dailyLimitMin.toDouble().clamp(15, 480),
                  min: 15,
                  max: 480,
                  divisions: 31,
                  label: '$_dailyLimitMin dk',
                  onChanged: (val) {
                    setState(() => _dailyLimitMin = val.round());
                  },
                ),
                Wrap(
                  spacing: 8,
                  children: [30, 60, 120, 180, 240].map((preset) {
                    return ChoiceChip(
                      label: Text('$preset dk'),
                      selected: _dailyLimitMin == preset,
                      onSelected: (_) {
                        setState(() => _dailyLimitMin = preset);
                      },
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Kesme Saati (Cutoff Window)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Kesme Saati Aralığı (Gece Modu)',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Belirtilen saat aralığında (gece yarısını aşabilir, örn. 23:00 - 06:00) telefon kullanıldığında uyarı gösterilir.',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pickTime(isStart: true),
                        icon: const Icon(Icons.nightlight_round),
                        label: Text('Başlangıç: $_cutoffStart'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pickTime(isStart: false),
                        icon: const Icon(Icons.wb_sunny_outlined),
                        label: Text('Bitiş: $_cutoffEnd'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Uyarı Modu (notify / overlay)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Uyarı Gösterim Modu',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                RadioListTile<RuleMode>(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Bildirim (notify)'),
                  subtitle: const Text('Standart sistem bildirimi gönderir.'),
                  value: RuleMode.notify,
                  groupValue: _mode,
                  onChanged: (val) {
                    if (val != null) setState(() => _mode = val);
                  },
                ),
                RadioListTile<RuleMode>(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Ekran Üstü Uyarı (overlay)'),
                  subtitle: const Text(
                    'Açık uygulamanın üzerinde tam ekran/pencere uyarı gösterir.',
                  ),
                  value: RuleMode.overlay,
                  groupValue: _mode,
                  onChanged: (val) {
                    if (val != null) setState(() => _mode = val);
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),

        FilledButton.icon(
          onPressed: _isSaving ? null : _saveRule,
          icon: _isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined),
          label: const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('Kuralı Kaydet ve Senkronize Et'),
          ),
        ),
      ],
    );
  }
}
