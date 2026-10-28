import 'package:flutter/material.dart';

/// Um medicamento cadastrado.
class Medication {
  Medication({
    this.id,
    required this.name,
    this.activeIngredient = '',
    this.strength,
    this.strengthUnit = 'mg',
    this.form = 'Comprimido',
    this.notes = '',
    this.stock,
    this.lowStockThreshold,
    this.active = true,
    this.color = 0xFF2E7D6B,
  });

  int? id;
  String name;
  String activeIngredient;

  /// Concentração/dosagem do medicamento (ex.: 500 para "500 mg").
  double? strength;
  String strengthUnit;

  /// Forma farmacêutica (comprimido, cápsula, gotas...). Também é a unidade
  /// usada no estoque e na quantidade de cada dose.
  String form;
  String notes;

  /// Estoque atual em unidades de [form]. `null` = estoque não controlado.
  double? stock;
  double? lowStockThreshold;
  bool active;
  int color;

  bool get tracksStock => stock != null;
  bool get isLowStock =>
      stock != null && lowStockThreshold != null && stock! <= lowStockThreshold!;

  String get strengthLabel {
    if (strength == null) return '';
    return '${formatNumber(strength!)} $strengthUnit';
  }

  /// "Losartana 50 mg"
  String get displayName =>
      strength == null ? name : '$name ${formatNumber(strength!)} $strengthUnit';

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'active_ingredient': activeIngredient,
        'strength': strength,
        'strength_unit': strengthUnit,
        'form': form,
        'notes': notes,
        'stock': stock,
        'low_stock_threshold': lowStockThreshold,
        'active': active ? 1 : 0,
        'color': color,
      };

  factory Medication.fromMap(Map<String, Object?> m) => Medication(
        id: m['id'] as int?,
        name: m['name'] as String,
        activeIngredient: (m['active_ingredient'] as String?) ?? '',
        strength: (m['strength'] as num?)?.toDouble(),
        strengthUnit: (m['strength_unit'] as String?) ?? 'mg',
        form: (m['form'] as String?) ?? 'Comprimido',
        notes: (m['notes'] as String?) ?? '',
        stock: (m['stock'] as num?)?.toDouble(),
        lowStockThreshold: (m['low_stock_threshold'] as num?)?.toDouble(),
        active: (m['active'] as int? ?? 1) == 1,
        color: (m['color'] as int?) ?? 0xFF2E7D6B,
      );
}

enum ScheduleType {
  daily('daily', 'Diariamente'),
  intervalDays('interval_days', 'A cada N dias'),
  weekly('weekly', 'Dias da semana'),
  intervalHours('interval_hours', 'A cada N horas');

  const ScheduleType(this.code, this.label);
  final String code;
  final String label;

  static ScheduleType fromCode(String code) =>
      values.firstWhere((t) => t.code == code, orElse: () => daily);
}

/// Agendamento (posologia) de um medicamento.
class Schedule {
  Schedule({
    this.id,
    required this.medicationId,
    this.type = ScheduleType.daily,
    this.interval = 1,
    this.weekdays = 0x7F,
    List<TimeOfDay>? times,
    this.dose = 1,
    required this.startDate,
    this.endDate,
    this.active = true,
  }) : times = times ?? [const TimeOfDay(hour: 8, minute: 0)];

  int? id;
  int medicationId;
  ScheduleType type;

  /// Dias (intervalDays) ou horas (intervalHours) entre doses.
  int interval;

  /// Máscara de dias da semana: bit 0 = segunda ... bit 6 = domingo.
  int weekdays;

  /// Horários do dia. Para [ScheduleType.intervalHours], apenas o primeiro é
  /// usado como horário de referência.
  List<TimeOfDay> times;

  /// Quantidade por dose, na unidade do medicamento (ex.: 1 comprimido, 0.5).
  double dose;

  /// Data de início (meia-noite local).
  DateTime startDate;
  DateTime? endDate;
  bool active;

  bool hasWeekday(int dartWeekday) => weekdays & (1 << (dartWeekday - 1)) != 0;

  String describe() {
    final t = times.map(formatTime).join(', ');
    switch (type) {
      case ScheduleType.daily:
        return 'Todos os dias às $t';
      case ScheduleType.intervalDays:
        return interval == 1
            ? 'Todos os dias às $t'
            : 'A cada $interval dias às $t';
      case ScheduleType.weekly:
        if (weekdays == 0x7F) return 'Todos os dias às $t';
        final days = [
          for (var d = 1; d <= 7; d++)
            if (hasWeekday(d)) weekdayShort[d - 1]
        ].join(', ');
        return '$days às $t';
      case ScheduleType.intervalHours:
        return 'A cada $interval h a partir de ${formatTime(times.first)}';
    }
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'medication_id': medicationId,
        'type': type.code,
        'interval': interval,
        'weekdays': weekdays,
        'times': times.map(formatTime).join(','),
        'dose': dose,
        'start_date': startDate.millisecondsSinceEpoch,
        'end_date': endDate?.millisecondsSinceEpoch,
        'active': active ? 1 : 0,
      };

  factory Schedule.fromMap(Map<String, Object?> m) => Schedule(
        id: m['id'] as int?,
        medicationId: m['medication_id'] as int,
        type: ScheduleType.fromCode(m['type'] as String),
        interval: (m['interval'] as int?) ?? 1,
        weekdays: (m['weekdays'] as int?) ?? 0x7F,
        times: (m['times'] as String)
            .split(',')
            .where((s) => s.contains(':'))
            .map(parseTime)
            .toList(),
        dose: (m['dose'] as num).toDouble(),
        startDate:
            DateTime.fromMillisecondsSinceEpoch(m['start_date'] as int),
        endDate: m['end_date'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(m['end_date'] as int),
        active: (m['active'] as int? ?? 1) == 1,
      );
}

enum DoseStatus {
  taken('taken', 'Tomada'),
  skipped('skipped', 'Pulada');

  const DoseStatus(this.code, this.label);
  final String code;
  final String label;

  static DoseStatus fromCode(String code) =>
      values.firstWhere((s) => s.code == code, orElse: () => taken);
}

/// Registro de uma dose tomada (ou pulada).
class DoseRecord {
  DoseRecord({
    this.id,
    required this.medicationId,
    this.scheduleId,
    this.scheduledAt,
    required this.takenAt,
    this.quantity = 1,
    this.status = DoseStatus.taken,
    this.notes = '',
  });

  int? id;
  int medicationId;
  int? scheduleId;

  /// Horário previsto pelo agendamento (null para doses avulsas).
  DateTime? scheduledAt;

  /// Data/hora real em que a dose foi tomada.
  DateTime takenAt;

  /// Quantidade tomada na unidade do medicamento (1 = inteiro, 0.5 = 1/2...).
  double quantity;
  DoseStatus status;
  String notes;

  /// Quanto esta dose consome do estoque.
  double get stockUsage => status == DoseStatus.taken ? quantity : 0;

  Map<String, Object?> toMap() => {
        'id': id,
        'medication_id': medicationId,
        'schedule_id': scheduleId,
        'scheduled_at': scheduledAt?.millisecondsSinceEpoch,
        'taken_at': takenAt.millisecondsSinceEpoch,
        'quantity': quantity,
        'status': status.code,
        'notes': notes,
      };

  factory DoseRecord.fromMap(Map<String, Object?> m) => DoseRecord(
        id: m['id'] as int?,
        medicationId: m['medication_id'] as int,
        scheduleId: m['schedule_id'] as int?,
        scheduledAt: m['scheduled_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(m['scheduled_at'] as int),
        takenAt: DateTime.fromMillisecondsSinceEpoch(m['taken_at'] as int),
        quantity: (m['quantity'] as num).toDouble(),
        status: DoseStatus.fromCode(m['status'] as String),
        notes: (m['notes'] as String?) ?? '',
      );
}

/// Aviso adiado ("soneca") de uma dose prevista.
class Snooze {
  Snooze({
    this.id,
    required this.scheduleId,
    required this.scheduledAt,
    required this.until,
  });

  int? id;
  int scheduleId;
  DateTime scheduledAt;
  DateTime until;

  Map<String, Object?> toMap() => {
        'id': id,
        'schedule_id': scheduleId,
        'scheduled_at': scheduledAt.millisecondsSinceEpoch,
        'until_at': until.millisecondsSinceEpoch,
      };

  factory Snooze.fromMap(Map<String, Object?> m) => Snooze(
        id: m['id'] as int?,
        scheduleId: m['schedule_id'] as int,
        scheduledAt:
            DateTime.fromMillisecondsSinceEpoch(m['scheduled_at'] as int),
        until: DateTime.fromMillisecondsSinceEpoch(m['until_at'] as int),
      );
}

// ---------------------------------------------------------------------------
// Formatação

const weekdayShort = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];

String two(int n) => n.toString().padLeft(2, '0');

String formatTime(TimeOfDay t) => '${two(t.hour)}:${two(t.minute)}';

TimeOfDay parseTime(String s) {
  final p = s.trim().split(':');
  return TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1]));
}

String formatNumber(double v) {
  if (v == v.roundToDouble()) return v.toInt().toString();
  return v
      .toStringAsFixed(2)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceAll('.', ',');
}

/// Frações comuns para exibição de quantidades (1/2, 1/3, 1/4...).
const commonFractions = <(int, int)>[
  (1, 4),
  (1, 3),
  (1, 2),
  (2, 3),
  (3, 4),
];

/// Formata uma quantidade como fração quando possível: 0.5 -> "1/2",
/// 1.5 -> "1 1/2", 1 -> "1".
String formatQuantity(double q) {
  final whole = q.floor();
  final frac = q - whole;
  if (frac.abs() < 0.005) return '$whole';
  if ((1 - frac).abs() < 0.005) return '${whole + 1}';
  for (final (n, d) in commonFractions) {
    if ((frac - n / d).abs() < 0.005) {
      return whole == 0 ? '$n/$d' : '$whole $n/$d';
    }
  }
  return formatNumber(q);
}

/// "1/2 comprimido", "2 comprimidos".
String formatDoseQuantity(double q, String form) {
  final unit = form.toLowerCase();
  String plural = unit;
  if (q > 1 && !unit.endsWith('s') && !unit.endsWith('l')) {
    plural = unit.endsWith('ão')
        ? '${unit.substring(0, unit.length - 2)}ões'
        : '${unit}s';
  }
  return '${formatQuantity(q)} $plural';
}

String formatDate(DateTime d) => '${two(d.day)}/${two(d.month)}/${d.year}';

String formatDateTime(DateTime d) =>
    '${formatDate(d)} ${two(d.hour)}:${two(d.minute)}';

String formatHm(DateTime d) => '${two(d.hour)}:${two(d.minute)}';

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
