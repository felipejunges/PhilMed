import 'package:flutter/material.dart';

import '../app_events.dart';
import '../db.dart';
import '../models.dart';
import '../notifications.dart';
import '../widgets/quantity_picker.dart';

/// Cria ou edita o registro de uma dose (data/hora real, quantidade, etc.).
class DoseFormScreen extends StatefulWidget {
  const DoseFormScreen({
    super.key,
    this.dose,
    this.medication,
    this.initialTakenAt,
  });

  /// Dose a editar. Se não tiver `id`, é um novo registro pré-preenchido.
  final DoseRecord? dose;
  final Medication? medication;
  final DateTime? initialTakenAt;

  @override
  State<DoseFormScreen> createState() => _DoseFormScreenState();
}

class _DoseFormScreenState extends State<DoseFormScreen> {
  List<Medication> _meds = [];
  Schedule? _schedule;
  int? _medId;
  late DateTime _takenAt;
  double _quantity = 1;
  DoseStatus _status = DoseStatus.taken;
  final _notes = TextEditingController();
  bool _saving = false;

  bool get _isEditing => widget.dose?.id != null;

  @override
  void initState() {
    super.initState();
    final d = widget.dose;
    _medId = d?.medicationId ?? widget.medication?.id;
    _takenAt = d?.takenAt ?? widget.initialTakenAt ?? DateTime.now();
    _quantity = d?.quantity ?? 1;
    _status = d?.status ?? DoseStatus.taken;
    _notes.text = d?.notes ?? '';
    _load();
  }

  Future<void> _load() async {
    final db = AppDatabase.instance;
    final meds = await db.medications();
    final sch = widget.dose?.scheduleId == null
        ? null
        : await db.schedule(widget.dose!.scheduleId!);
    if (!mounted) return;
    setState(() {
      _meds = meds;
      _schedule = sch;
      _medId ??= meds.where((m) => m.active).firstOrNull?.id;
    });
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Medication? get _med => _meds.where((m) => m.id == _medId).firstOrNull;

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _takenAt,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_takenAt),
    );
    if (time == null) return;
    setState(() => _takenAt =
        DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  Future<void> _save() async {
    if (_medId == null) return;
    setState(() => _saving = true);
    final d = widget.dose;
    final dose = DoseRecord(
      id: d?.id,
      medicationId: _medId!,
      scheduleId: d?.scheduleId,
      scheduledAt: d?.scheduledAt,
      takenAt: _takenAt,
      quantity: _quantity,
      status: _status,
      notes: _notes.text.trim(),
    );
    await AppDatabase.instance.saveDose(dose);
    if (dose.scheduleId != null && dose.scheduledAt != null) {
      await clearOccurrenceNotifications(
          OccurrenceRef(dose.scheduleId!, dose.scheduledAt!));
    }
    await AppEvents.dataChanged();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir registro?'),
        content: const Text(
            'A quantidade será devolvida ao estoque, se ele for controlado.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Excluir')),
        ],
      ),
    );
    if (ok != true) return;
    await AppDatabase.instance.deleteDose(widget.dose!);
    await AppEvents.dataChanged();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final med = _med;
    final fromSchedule = widget.dose?.scheduledAt != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Editar dose' : 'Registrar dose'),
        actions: [
          if (_isEditing)
            IconButton(
              tooltip: 'Excluir',
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (fromSchedule)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                  'Dose prevista para ${formatDateTime(widget.dose!.scheduledAt!)}',
                  style: Theme.of(context).textTheme.titleSmall),
            ),
          DropdownButtonFormField<int>(
            initialValue: _medId,
            decoration: const InputDecoration(
                labelText: 'Medicamento', border: OutlineInputBorder()),
            items: [
              for (final m in _meds)
                DropdownMenuItem(value: m.id, child: Text(m.displayName)),
            ],
            onChanged: fromSchedule ? null : (v) => setState(() => _medId = v),
          ),
          const SizedBox(height: 16),
          SegmentedButton<DoseStatus>(
            segments: const [
              ButtonSegment(
                  value: DoseStatus.taken,
                  icon: Icon(Icons.check),
                  label: Text('Tomada')),
              ButtonSegment(
                  value: DoseStatus.skipped,
                  icon: Icon(Icons.block),
                  label: Text('Pulada')),
            ],
            selected: {_status},
            onSelectionChanged: (s) => setState(() => _status = s.first),
          ),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event),
            title: Text(_status == DoseStatus.taken
                ? 'Data e hora em que tomou'
                : 'Data e hora do registro'),
            subtitle: Text(formatDateTime(_takenAt)),
            trailing: const Icon(Icons.edit),
            onTap: _pickDateTime,
          ),
          if (_status == DoseStatus.taken) ...[
            const SizedBox(height: 8),
            Text('Proporção tomada',
                style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            QuantityPicker(
              value: _quantity,
              unit: med?.form.toLowerCase(),
              reference: _schedule?.dose ?? 1,
              onChanged: (q) => setState(() => _quantity = q),
            ),
          ],
          const SizedBox(height: 16),
          TextField(
            controller: _notes,
            decoration: const InputDecoration(
                labelText: 'Observações', border: OutlineInputBorder()),
            maxLines: 2,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _saving || _medId == null ? null : _save,
            icon: const Icon(Icons.save),
            label: const Text('Salvar'),
          ),
        ],
      ),
    );
  }
}
