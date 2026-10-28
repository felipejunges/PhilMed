import 'package:flutter/material.dart';

import '../app_events.dart';
import '../db.dart';
import '../main.dart';
import '../models.dart';
import '../notifications.dart';
import '../scheduler.dart';
import 'dose_form_screen.dart';

/// Agenda do dia: doses previstas, tomadas, puladas e atrasadas.
class TodayScreen extends StatefulWidget {
  const TodayScreen({super.key});

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  DateTime _day = dateOnly(DateTime.now());
  List<Occurrence> _agenda = [];
  List<DoseRecord> _extras = [];
  Map<int, Medication> _meds = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    AppEvents.revision.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    AppEvents.revision.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final next = DateTime(_day.year, _day.month, _day.day + 1);
    final agenda = await buildAgenda(_day, next);
    final keys = agenda.map((o) => o.key).toSet();
    final doses = await AppDatabase.instance.doses(from: _day, to: next);
    final meds = {
      for (final m in await AppDatabase.instance.medications()) m.id!: m
    };
    if (!mounted) return;
    setState(() {
      _agenda = agenda;
      _extras = doses
          .where((d) =>
              d.scheduleId == null ||
              d.scheduledAt == null ||
              !keys.contains(occurrenceKey(d.scheduleId!, d.scheduledAt!)))
          .toList();
      _meds = meds;
      _loading = false;
    });
  }

  void _shiftDay(int delta) {
    setState(() => _day = DateTime(_day.year, _day.month, _day.day + delta));
    _load();
  }

  String _dayTitle() {
    final today = dateOnly(DateTime.now());
    final diff = _day.difference(today).inDays;
    if (diff == 0) return 'Hoje';
    if (diff == -1) return 'Ontem';
    if (diff == 1) return 'Amanhã';
    return '${weekdayShort[_day.weekday - 1]}, ${formatDate(_day)}';
  }

  @override
  Widget build(BuildContext context) {
    final lowStock = _meds.values.where((m) => m.active && m.isLowStock);
    final items = <_Item>[
      for (final o in _agenda) _Item(o.at, occurrence: o),
      for (final d in _extras) _Item(d.takenAt, extra: d),
    ]..sort((a, b) => a.at.compareTo(b.at));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Agenda'),
        actions: [settingsAction(context)],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                IconButton(
                    onPressed: () => _shiftDay(-1),
                    icon: const Icon(Icons.chevron_left)),
                Expanded(
                  child: TextButton(
                    onPressed: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: _day,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (d != null) {
                        setState(() => _day = d);
                        _load();
                      }
                    },
                    child: Text(_dayTitle(),
                        style: Theme.of(context).textTheme.titleMedium),
                  ),
                ),
                IconButton(
                    onPressed: () => _shiftDay(1),
                    icon: const Icon(Icons.chevron_right)),
              ],
            ),
          ),
          for (final m in lowStock)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.inventory_2_outlined),
                title: Text('Estoque baixo: ${m.displayName}'),
                subtitle: Text(
                    'Restam ${formatDoseQuantity(m.stock!, m.form)}'),
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : items.isEmpty
                    ? const _Empty()
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.builder(
                          padding: const EdgeInsets.only(bottom: 88),
                          itemCount: items.length,
                          itemBuilder: (_, i) {
                            final it = items[i];
                            if (it.occurrence != null) {
                              return _OccurrenceTile(it.occurrence!);
                            }
                            return _ExtraTile(
                                it.extra!, _meds[it.extra!.medicationId]);
                          },
                        ),
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => DoseFormScreen(
                  initialTakenAt: dateOnly(DateTime.now()) == _day
                      ? DateTime.now()
                      : DateTime(_day.year, _day.month, _day.day, 12),
                ))),
        icon: const Icon(Icons.add),
        label: const Text('Dose avulsa'),
      ),
    );
  }
}

class _Item {
  _Item(this.at, {this.occurrence, this.extra});
  final DateTime at;
  final Occurrence? occurrence;
  final DoseRecord? extra;
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Text(
          'Nenhuma dose prevista para este dia.\n\n'
          'Cadastre um medicamento e seus horários na aba Medicamentos.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _OccurrenceTile extends StatelessWidget {
  const _OccurrenceTile(this.o);
  final Occurrence o;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final r = o.record;
    IconData icon;
    Color color;
    String status;
    if (r != null && r.status == DoseStatus.taken) {
      icon = Icons.check_circle;
      color = Colors.green;
      status = 'Tomada às ${formatHm(r.takenAt)}'
          '${dateOnly(r.takenAt) != dateOnly(o.at) ? ' de ${formatDate(r.takenAt)}' : ''}'
          ' · ${formatDoseQuantity(r.quantity, o.medication.form)}';
    } else if (r != null) {
      icon = Icons.block;
      color = cs.outline;
      status = 'Pulada';
    } else if (o.snooze != null && o.snooze!.until.isAfter(DateTime.now())) {
      icon = Icons.snooze;
      color = Colors.orange;
      status = 'Adiada até ${formatHm(o.snooze!.until)}';
    } else if (o.isOverdue) {
      icon = Icons.error_outline;
      color = cs.error;
      status = 'Atrasada';
    } else {
      icon = Icons.schedule;
      color = cs.primary;
      status = 'Pendente';
    }

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Color(o.medication.color).withValues(alpha: 0.2),
        child: Text(formatHm(o.at),
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface)),
      ),
      title: Text(o.medication.displayName),
      subtitle: Text(
          '${formatDoseQuantity(o.schedule.dose, o.medication.form)} · $status'),
      trailing: Icon(icon, color: color),
      onTap: () =>
          openOccurrenceSheet(context, OccurrenceRef(o.schedule.id!, o.at)),
    );
  }
}

class _ExtraTile extends StatelessWidget {
  const _ExtraTile(this.d, this.med);
  final DoseRecord d;
  final Medication? med;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor:
            Color(med?.color ?? 0xFF888888).withValues(alpha: 0.2),
        child: Text(formatHm(d.takenAt),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
      ),
      title: Text(med?.displayName ?? 'Medicamento removido'),
      subtitle: Text(
          'Dose avulsa · ${formatDoseQuantity(d.quantity, med?.form ?? 'un.')}'),
      trailing: const Icon(Icons.check_circle_outline, color: Colors.green),
      onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => DoseFormScreen(dose: d))),
    );
  }
}

/// Folha de ações de uma dose prevista: tomei, adiar, pular, editar.
Future<void> openOccurrenceSheet(BuildContext context, OccurrenceRef ref) async {
  final db = AppDatabase.instance;
  final s = await db.schedule(ref.scheduleId);
  if (s == null) return;
  final m = await db.medication(s.medicationId);
  if (m == null) return;
  final record = await db.doseForOccurrence(ref.scheduleId, ref.at);
  if (!context.mounted) return;

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) {
      Future<void> done(Future<void> action) async {
        await action;
        await AppEvents.dataChanged();
        if (ctx.mounted) Navigator.of(ctx).pop();
      }

      void openForm(DoseRecord dose) {
        Navigator.of(ctx).pop();
        Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => DoseFormScreen(dose: dose, medication: m)));
      }

      final text = Theme.of(ctx).textTheme;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(m.displayName, style: text.titleLarge),
              const SizedBox(height: 4),
              Text('Previsto para ${formatDateTime(ref.at)} · '
                  '${formatDoseQuantity(s.dose, m.form)}'),
              if (record != null) ...[
                const SizedBox(height: 8),
                Text(
                  record.status == DoseStatus.taken
                      ? 'Tomada em ${formatDateTime(record.takenAt)} · '
                          '${formatDoseQuantity(record.quantity, m.form)}'
                      : 'Marcada como pulada',
                  style: text.titleSmall,
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => openForm(record),
                  icon: const Icon(Icons.edit),
                  label: const Text('Editar registro'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => done(db.deleteDose(record)),
                  icon: const Icon(Icons.undo),
                  label: const Text('Desfazer (excluir registro)'),
                ),
              ] else ...[
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => done(markTaken(ref)),
                  icon: const Icon(Icons.check),
                  label: const Text('Tomei agora'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => openForm(DoseRecord(
                    medicationId: m.id!,
                    scheduleId: s.id,
                    scheduledAt: ref.at,
                    takenAt: DateTime.now(),
                    quantity: s.dose,
                  )),
                  icon: const Icon(Icons.edit_calendar),
                  label: const Text('Tomei em outro horário / quantidade…'),
                ),
                const SizedBox(height: 16),
                Text('Adiar aviso', style: text.labelLarge),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final min in snoozeOptions)
                      ActionChip(
                        avatar: const Icon(Icons.snooze, size: 18),
                        label: Text('$min min'),
                        onPressed: () => done(snoozeOccurrence(ref, min)),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () => done(markSkipped(ref)),
                  icon: const Icon(Icons.block),
                  label: const Text('Pular esta dose'),
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}
