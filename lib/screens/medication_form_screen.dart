import 'package:flutter/material.dart';

import '../app_events.dart';
import '../db.dart';
import '../models.dart';
import '../widgets/quantity_picker.dart';
import 'schedule_form_screen.dart';

const medicationForms = [
  'Comprimido',
  'Cápsula',
  'Drágea',
  'Gota',
  'ml',
  'Sachê',
  'Ampola',
  'Aplicação',
  'Jato',
  'Adesivo',
  'Unidade',
];

const strengthUnits = ['mg', 'mcg', 'g', 'mg/ml', 'UI', '%', 'ml'];

const medicationColors = [
  0xFF2E7D6B,
  0xFF1565C0,
  0xFF6A1B9A,
  0xFFC62828,
  0xFFEF6C00,
  0xFFF9A825,
  0xFF558B2F,
  0xFF00838F,
  0xFFAD1457,
  0xFF5D4037,
];

/// Cadastro/edição de medicamento, incluindo seus horários.
class MedicationFormScreen extends StatefulWidget {
  const MedicationFormScreen({super.key, this.medication});
  final Medication? medication;

  @override
  State<MedicationFormScreen> createState() => _MedicationFormScreenState();
}

class _MedicationFormScreenState extends State<MedicationFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final Medication _m;
  final _name = TextEditingController();
  final _ingredient = TextEditingController();
  final _strength = TextEditingController();
  final _notes = TextEditingController();
  final _stock = TextEditingController();
  final _lowStock = TextEditingController();
  bool _trackStock = false;
  List<Schedule> _schedules = [];
  final List<int> _deletedSchedules = [];
  bool _saving = false;

  bool get _isNew => widget.medication?.id == null;

  @override
  void initState() {
    super.initState();
    final src = widget.medication;
    _m = src == null
        ? Medication(name: '')
        : Medication.fromMap(src.toMap());
    _name.text = _m.name;
    _ingredient.text = _m.activeIngredient;
    _strength.text = _m.strength == null ? '' : formatNumber(_m.strength!);
    _notes.text = _m.notes;
    _trackStock = _m.stock != null;
    _stock.text = _m.stock == null ? '' : formatQuantity(_m.stock!);
    _lowStock.text = _m.lowStockThreshold == null
        ? ''
        : formatQuantity(_m.lowStockThreshold!);
    if (!_isNew) {
      AppDatabase.instance
          .schedules(medicationId: _m.id)
          .then((s) => setState(() => _schedules = s));
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _ingredient, _strength, _notes, _stock, _lowStock]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _editSchedule([int? index]) async {
    final current = index == null ? null : _schedules[index];
    final result = await Navigator.of(context).push<Schedule>(
      MaterialPageRoute(
        builder: (_) => ScheduleFormScreen(
          schedule: current,
          unit: _m.form,
          medicationId: _m.id ?? 0,
        ),
      ),
    );
    if (result == null) return;
    setState(() {
      if (index == null) {
        _schedules.add(result);
      } else {
        _schedules[index] = result;
      }
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    _m
      ..name = _name.text.trim()
      ..activeIngredient = _ingredient.text.trim()
      ..strength = double.tryParse(_strength.text.replaceAll(',', '.'))
      ..notes = _notes.text.trim()
      ..stock = _trackStock ? (parseQuantity(_stock.text) ?? 0) : null
      ..lowStockThreshold = _trackStock ? parseQuantity(_lowStock.text) : null;

    final db = AppDatabase.instance;
    final id = await db.saveMedication(_m);
    for (final sid in _deletedSchedules) {
      await db.deleteSchedule(sid);
    }
    for (final s in _schedules) {
      s.medicationId = id;
      await db.saveSchedule(s);
    }
    await AppEvents.dataChanged();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir medicamento?'),
        content: const Text(
            'Todos os horários e o histórico de doses deste medicamento '
            'também serão excluídos.\n\nSe você só parou de tomar, prefira '
            'desmarcar "Ativo" para manter o histórico.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.error),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Excluir')),
        ],
      ),
    );
    if (ok != true) return;
    await AppDatabase.instance.deleteMedication(_m.id!);
    await AppEvents.dataChanged();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    const gap = SizedBox(height: 12);
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'Novo medicamento' : 'Editar medicamento'),
        actions: [
          if (!_isNew)
            IconButton(
              tooltip: 'Excluir',
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                  labelText: 'Nome *', border: OutlineInputBorder()),
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? 'Informe o nome' : null,
            ),
            gap,
            TextFormField(
              controller: _ingredient,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                  labelText: 'Princípio ativo', border: OutlineInputBorder()),
            ),
            gap,
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    controller: _strength,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                        labelText: 'Dosagem', border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<String>(
                    initialValue: strengthUnits.contains(_m.strengthUnit)
                        ? _m.strengthUnit
                        : 'mg',
                    decoration: const InputDecoration(
                        labelText: 'Unidade', border: OutlineInputBorder()),
                    items: [
                      for (final u in strengthUnits)
                        DropdownMenuItem(value: u, child: Text(u)),
                    ],
                    onChanged: (v) => _m.strengthUnit = v ?? 'mg',
                  ),
                ),
              ],
            ),
            gap,
            DropdownButtonFormField<String>(
              initialValue:
                  medicationForms.contains(_m.form) ? _m.form : 'Unidade',
              decoration: const InputDecoration(
                  labelText: 'Forma (unidade da dose e do estoque)',
                  border: OutlineInputBorder()),
              items: [
                for (final f in medicationForms)
                  DropdownMenuItem(value: f, child: Text(f)),
              ],
              onChanged: (v) => setState(() => _m.form = v ?? 'Comprimido'),
            ),
            gap,
            TextFormField(
              controller: _notes,
              maxLines: 2,
              decoration: const InputDecoration(
                  labelText: 'Observações (ex.: tomar em jejum)',
                  border: OutlineInputBorder()),
            ),
            gap,
            Text('Cor', style: text.labelLarge),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in medicationColors)
                  GestureDetector(
                    onTap: () => setState(() => _m.color = c),
                    child: CircleAvatar(
                      radius: 16,
                      backgroundColor: Color(c),
                      child: _m.color == c
                          ? const Icon(Icons.check,
                              size: 18, color: Colors.white)
                          : null,
                    ),
                  ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Ativo'),
              subtitle: const Text('Desative para parar os avisos sem perder '
                  'o histórico'),
              value: _m.active,
              onChanged: (v) => setState(() => _m.active = v),
            ),
            const Divider(),
            Row(
              children: [
                Expanded(child: Text('Horários', style: text.titleMedium)),
                TextButton.icon(
                  onPressed: () => _editSchedule(),
                  icon: const Icon(Icons.add_alarm),
                  label: const Text('Adicionar'),
                ),
              ],
            ),
            if (_schedules.isEmpty)
              const Text('Nenhum horário. Sem horários, o app não envia '
                  'avisos para este medicamento.'),
            for (var i = 0; i < _schedules.length; i++)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                    _schedules[i].active ? Icons.alarm : Icons.alarm_off),
                title: Text(_schedules[i].describe()),
                subtitle: Text(formatDoseQuantity(_schedules[i].dose, _m.form)),
                onTap: () => _editSchedule(i),
                trailing: IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Remover horário',
                  onPressed: () => setState(() {
                    final removed = _schedules.removeAt(i);
                    if (removed.id != null) _deletedSchedules.add(removed.id!);
                  }),
                ),
              ),
            const Divider(),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Controlar estoque'),
              subtitle: const Text('Desconta automaticamente a cada dose '
                  'tomada'),
              value: _trackStock,
              onChanged: (v) => setState(() => _trackStock = v),
            ),
            if (_trackStock) ...[
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _stock,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      decoration: InputDecoration(
                          labelText: 'Estoque atual',
                          suffixText: _m.form.toLowerCase(),
                          border: const OutlineInputBorder()),
                      validator: (v) => _trackStock &&
                              parseQuantity(v ?? '') == null
                          ? 'Número inválido'
                          : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _lowStock,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      decoration: const InputDecoration(
                          labelText: 'Avisar abaixo de',
                          border: OutlineInputBorder()),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.save),
              label: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
  }
}
