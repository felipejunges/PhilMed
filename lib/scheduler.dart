import 'db.dart';
import 'models.dart';

/// Horários previstos de [s] no intervalo [from, to).
List<DateTime> occurrencesBetween(Schedule s, DateTime from, DateTime to) {
  final result = <DateTime>[];
  if (!s.active || s.times.isEmpty || !from.isBefore(to)) return result;
  final start = dateOnly(s.startDate);
  final endExclusive = s.endDate == null
      ? null
      : dateOnly(s.endDate!).add(const Duration(days: 1));

  bool inRange(DateTime dt) =>
      !dt.isBefore(from) &&
      dt.isBefore(to) &&
      !dt.isBefore(start) &&
      (endExclusive == null || dt.isBefore(endExclusive));

  if (s.type == ScheduleType.intervalHours) {
    final step = Duration(hours: s.interval < 1 ? 1 : s.interval);
    final t = s.times.first;
    final anchor = DateTime(start.year, start.month, start.day, t.hour, t.minute);
    var k = 0;
    if (from.isAfter(anchor)) {
      k = (from.difference(anchor).inMinutes / step.inMinutes).floor();
    }
    for (var dt = anchor.add(step * k); dt.isBefore(to); dt = dt.add(step)) {
      if (inRange(dt)) result.add(dt);
    }
    return result;
  }

  var day = dateOnly(from);
  if (day.isBefore(start)) day = start;
  final lastDay = dateOnly(to);
  while (!day.isAfter(lastDay)) {
    if (_dayMatches(s, day, start)) {
      for (final t in s.times) {
        final dt = DateTime(day.year, day.month, day.day, t.hour, t.minute);
        if (inRange(dt)) result.add(dt);
      }
    }
    day = DateTime(day.year, day.month, day.day + 1);
  }
  result.sort();
  return result;
}

bool _dayMatches(Schedule s, DateTime day, DateTime start) {
  switch (s.type) {
    case ScheduleType.daily:
      return true;
    case ScheduleType.intervalDays:
      final n = s.interval < 1 ? 1 : s.interval;
      return _daysBetween(start, day) % n == 0;
    case ScheduleType.weekly:
      return s.hasWeekday(day.weekday);
    case ScheduleType.intervalHours:
      return true;
  }
}

int _daysBetween(DateTime a, DateTime b) =>
    DateTime.utc(b.year, b.month, b.day)
        .difference(DateTime.utc(a.year, a.month, a.day))
        .inDays;

/// Uma dose prevista na agenda, com seu eventual registro/adiamento.
class Occurrence {
  Occurrence({
    required this.medication,
    required this.schedule,
    required this.at,
    this.record,
    this.snooze,
  });

  final Medication medication;
  final Schedule schedule;
  final DateTime at;
  final DoseRecord? record;
  final Snooze? snooze;

  String get key => occurrenceKey(schedule.id!, at);
  bool get isDone => record != null;
  bool get isOverdue =>
      record == null &&
      DateTime.now().isAfter(at.add(const Duration(minutes: 1)));
}

/// Monta a agenda (ocorrências previstas) dos medicamentos ativos em
/// [from, to), cruzando com doses registradas e adiamentos.
Future<List<Occurrence>> buildAgenda(DateTime from, DateTime to) async {
  final db = AppDatabase.instance;
  final meds = {
    for (final m in await db.medications(onlyActive: true)) m.id!: m
  };
  final schedules = await db.schedules();

  final records = <String, DoseRecord>{};
  for (final d in await db.doses(
      from: from.subtract(const Duration(days: 1)), to: to)) {
    if (d.scheduleId != null && d.scheduledAt != null) {
      records[occurrenceKey(d.scheduleId!, d.scheduledAt!)] = d;
    }
  }
  final snoozes = {
    for (final s in await db.snoozes()) occurrenceKey(s.scheduleId, s.scheduledAt): s
  };

  final list = <Occurrence>[];
  for (final s in schedules) {
    final med = meds[s.medicationId];
    if (med == null) continue;
    for (final at in occurrencesBetween(s, from, to)) {
      final key = occurrenceKey(s.id!, at);
      list.add(Occurrence(
        medication: med,
        schedule: s,
        at: at,
        record: records[key],
        snooze: snoozes[key],
      ));
    }
  }
  list.sort((a, b) {
    final c = a.at.compareTo(b.at);
    return c != 0 ? c : a.medication.name.compareTo(b.medication.name);
  });
  return list;
}
