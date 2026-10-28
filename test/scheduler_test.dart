import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:philmed/models.dart';
import 'package:philmed/scheduler.dart';
import 'package:philmed/widgets/quantity_picker.dart';

Schedule _s(ScheduleType type,
        {int interval = 1,
        int weekdays = 0x7F,
        List<TimeOfDay>? times,
        DateTime? start,
        DateTime? end}) =>
    Schedule(
      id: 1,
      medicationId: 1,
      type: type,
      interval: interval,
      weekdays: weekdays,
      times: times ?? [const TimeOfDay(hour: 8, minute: 0)],
      startDate: start ?? DateTime(2026, 10, 1),
      endDate: end,
    );

void main() {
  group('occurrencesBetween', () {
    test('diário com dois horários', () {
      final s = _s(ScheduleType.daily, times: const [
        TimeOfDay(hour: 8, minute: 0),
        TimeOfDay(hour: 20, minute: 0),
      ]);
      final r = occurrencesBetween(
          s, DateTime(2026, 10, 5), DateTime(2026, 10, 7));
      expect(r, [
        DateTime(2026, 10, 5, 8),
        DateTime(2026, 10, 5, 20),
        DateTime(2026, 10, 6, 8),
        DateTime(2026, 10, 6, 20),
      ]);
    });

    test('a cada 2 dias, contado a partir do início', () {
      final s = _s(ScheduleType.intervalDays, interval: 2);
      final r = occurrencesBetween(
          s, DateTime(2026, 10, 1), DateTime(2026, 10, 8));
      expect(r.map((d) => d.day), [1, 3, 5, 7]);
    });

    test('semanal: segunda e quinta', () {
      final s = _s(ScheduleType.weekly, weekdays: (1 << 0) | (1 << 3));
      // 2026-10-05 é segunda-feira.
      final r = occurrencesBetween(
          s, DateTime(2026, 10, 5), DateTime(2026, 10, 19));
      expect(r.map((d) => d.day), [5, 8, 12, 15]);
    });

    test('a cada 8 horas', () {
      final s = _s(ScheduleType.intervalHours,
          interval: 8, times: const [TimeOfDay(hour: 6, minute: 0)]);
      final r = occurrencesBetween(
          s, DateTime(2026, 10, 3, 10), DateTime(2026, 10, 4, 7));
      expect(r, [
        DateTime(2026, 10, 3, 14),
        DateTime(2026, 10, 3, 22),
        DateTime(2026, 10, 4, 6),
      ]);
    });

    test('respeita data de término e início', () {
      final s = _s(ScheduleType.daily,
          start: DateTime(2026, 10, 3), end: DateTime(2026, 10, 4));
      final r = occurrencesBetween(
          s, DateTime(2026, 10, 1), DateTime(2026, 10, 10));
      expect(r.map((d) => d.day), [3, 4]);
    });

    test('agendamento inativo não gera ocorrências', () {
      final s = _s(ScheduleType.daily)..active = false;
      expect(
          occurrencesBetween(s, DateTime(2026, 10, 1), DateTime(2026, 10, 9)),
          isEmpty);
    });
  });

  group('quantidades', () {
    test('parse', () {
      expect(parseQuantity('1/2'), 0.5);
      expect(parseQuantity('1 1/2'), 1.5);
      expect(parseQuantity('0,25'), 0.25);
      expect(parseQuantity('3'), 3);
      expect(parseQuantity('1/0'), isNull);
      expect(parseQuantity('abc'), isNull);
    });

    test('format', () {
      expect(formatQuantity(0.5), '1/2');
      expect(formatQuantity(1 / 3), '1/3');
      expect(formatQuantity(1.25), '1 1/4');
      expect(formatQuantity(2), '2');
      expect(formatDoseQuantity(0.5, 'Comprimido'), '1/2 comprimido');
      expect(formatDoseQuantity(2, 'Cápsula'), '2 cápsulas');
      expect(formatDoseQuantity(10, 'ml'), '10 ml');
    });
  });
}
