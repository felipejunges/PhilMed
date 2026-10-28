import 'package:flutter/material.dart';

import '../models.dart';
import '../widgets/quantity_picker.dart';

/// Edita um agendamento. Devolve o [Schedule] via `Navigator.pop`; quem chama
/// é responsável por salvar.
class ScheduleFormScreen extends StatefulWidget {
  const ScheduleFormScreen({
    super.key,
    this.schedule,
    required this.unit,
    required this.medicationId,
  });

  final Schedule? schedule;
  final String unit;
  final int medicationId;

  @override
  State<ScheduleFormScreen> createState() => _ScheduleFormScreenState();
}

class _ScheduleFormScreenState extends State<ScheduleFormScreen> {
  late final Schedule _s;
  final _interval = TextEditingController();

  @override
  void initState() {
    super.initState();
    final src = widget.schedule;
    _s = src == null
        ? Schedule(
            medicationId: widget.medicationId,
            startDate: dateOnly(DateTime.now()),
          )
        : Schedule.fromMap(src.toMap());
    if (_s.type == ScheduleType.intervalDays && _s.interval < 2) {
      _s.interval = 2;
    }
    _interval.text = '${_s.interval}';
  }

  @override
  void dispose() {
    _interval.dispose();
    super.dispose();
  }

  void _setType(ScheduleType t) {
    setState(() {
      _s.type = t;
      if (t == ScheduleType.intervalDays && _s.interval < 2) _s.interval = 2;
      if (t == ScheduleType.intervalHours) {
        if (_s.interval < 1 || _s.interval > 24) _s.interval = 8;
        _s.times = [_s.times.first];
      }
      _interval.text = '${_s.interval}';
    });
  }

  Future<void> _addTime() async {
    final t = await showTimePicker(
        context: context, initialTime: const TimeOfDay(hour: 8, minute: 0));
    if (t == null) return;
    setState(() {
      if (!_s.times.contains(t)) _s.times.add(t);
      _s.times.sort((a, b) =>
          (a.hour * 60 + a.minute).compareTo(b.hour * 60 + b.minute));
    });
  }

  Future<void> _editTime(int i) async {
    final t = await showTimePicker(context: context, initialTime: _s.times[i]);
    if (t == null) return;
    setState(() {
      _s.times[i] = t;
      _s.times.sort((a, b) =>
          (a.hour * 60 + a.minute).compareTo(b.hour * 60 + b.minute));
    });
  }

  Future<void> _pickDate({required bool end}) async {
    final d = await showDatePicker(
      context: context,
      initialDate: end ? (_s.endDate ?? _s.startDate) : _s.startDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (d == null) return;
    setState(() {
      if (end) {
        _s.endDate = d;
      } else {
        _s.startDate = d;
      }
    });
  }

  void _save() {
    final n = int.tryParse(_interval.text) ?? 0;
    String? error;
    if (_s.type == ScheduleType.intervalDays && n < 1) {
      error = 'Informe o intervalo em dias.';
    } else if (_s.type == ScheduleType.intervalHours && (n < 1 || n > 168)) {
      error = 'Informe um intervalo entre 1 e 168 horas.';
    } else if (_s.type == ScheduleType.weekly && _s.weekdays == 0) {
      error = 'Escolha ao menos um dia da semana.';
    } else if (_s.times.isEmpty) {
      error = 'Adicione ao menos um horário.';
    } else if (_s.endDate != null && _s.endDate!.isBefore(_s.startDate)) {
      error = 'A data final é anterior à inicial.';
    }
    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    if (_s.type == ScheduleType.intervalDays ||
        _s.type == ScheduleType.intervalHours) {
      _s.interval = n;
    } else {
      _s.interval = 1;
    }
    Navigator.of(context).pop(_s);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    const gap = SizedBox(height: 16);
    final isHours = _s.type == ScheduleType.intervalHours;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.schedule == null ? 'Novo horário' : 'Editar horário'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Frequência', style: text.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final t in ScheduleType.values)
                ChoiceChip(
                  label: Text(t.label),
                  selected: _s.type == t,
                  onSelected: (_) => _setType(t),
                ),
            ],
          ),
          gap,
          if (_s.type == ScheduleType.intervalDays ||
              _s.type == ScheduleType.intervalHours)
            TextField(
              controller: _interval,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: isHours ? 'A cada quantas horas' : 'A cada quantos dias',
                suffixText: isHours ? 'horas' : 'dias',
                border: const OutlineInputBorder(),
              ),
            ),
          if (_s.type == ScheduleType.weekly)
            Wrap(
              spacing: 6,
              children: [
                for (var d = 1; d <= 7; d++)
                  FilterChip(
                    label: Text(weekdayShort[d - 1]),
                    selected: _s.hasWeekday(d),
                    onSelected: (v) => setState(() {
                      final bit = 1 << (d - 1);
                      _s.weekdays = v ? _s.weekdays | bit : _s.weekdays & ~bit;
                    }),
                  ),
              ],
            ),
          gap,
          Row(
            children: [
              Expanded(
                child: Text(isHours ? 'Primeiro horário' : 'Horários',
                    style: text.labelLarge),
              ),
              if (!isHours)
                TextButton.icon(
                  onPressed: _addTime,
                  icon: const Icon(Icons.add),
                  label: const Text('Horário'),
                ),
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (var i = 0; i < _s.times.length; i++)
                InputChip(
                  avatar: const Icon(Icons.alarm, size: 18),
                  label: Text(formatTime(_s.times[i])),
                  onPressed: () => _editTime(i),
                  onDeleted: _s.times.length > 1
                      ? () => setState(() => _s.times.removeAt(i))
                      : null,
                ),
            ],
          ),
          if (isHours)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Ex.: a cada 8 h a partir de 06:00 → 06:00, 14:00, 22:00.',
                style: text.bodySmall,
              ),
            ),
          gap,
          Text('Quantidade por dose', style: text.labelLarge),
          const SizedBox(height: 8),
          QuantityPicker(
            value: _s.dose,
            unit: widget.unit.toLowerCase(),
            onChanged: (q) => setState(() => _s.dose = q),
          ),
          gap,
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.play_arrow),
            title: const Text('Início'),
            subtitle: Text(formatDate(_s.startDate)),
            onTap: () => _pickDate(end: false),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.stop),
            title: const Text('Término'),
            subtitle: Text(_s.endDate == null
                ? 'Uso contínuo'
                : formatDate(_s.endDate!)),
            onTap: () => _pickDate(end: true),
            trailing: _s.endDate == null
                ? null
                : IconButton(
                    tooltip: 'Uso contínuo',
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _s.endDate = null),
                  ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Ativo'),
            value: _s.active,
            onChanged: (v) => setState(() => _s.active = v),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.check),
            label: const Text('Confirmar'),
          ),
        ],
      ),
    );
  }
}
