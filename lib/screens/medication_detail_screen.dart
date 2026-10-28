import 'package:flutter/material.dart';

import '../app_events.dart';
import '../db.dart';
import '../models.dart';
import '../widgets/quantity_picker.dart';
import 'dose_form_screen.dart';
import 'medication_form_screen.dart';

/// Detalhes de um medicamento: horários, estoque e últimas doses.
class MedicationDetailScreen extends StatefulWidget {
  const MedicationDetailScreen(this.medicationId, {super.key});
  final int medicationId;

  @override
  State<MedicationDetailScreen> createState() => _MedicationDetailScreenState();
}

class _MedicationDetailScreenState extends State<MedicationDetailScreen> {
  Medication? _med;
  List<Schedule> _schedules = [];
  List<DoseRecord> _doses = [];

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
    final db = AppDatabase.instance;
    final med = await db.medication(widget.medicationId);
    final schedules = await db.schedules(medicationId: widget.medicationId);
    final doses =
        await db.doses(medicationId: widget.medicationId, limit: 30);
    if (!mounted) return;
    if (med == null) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _med = med;
      _schedules = schedules;
      _doses = doses;
    });
  }

  Future<void> _editStock({required bool add}) async {
    final m = _med!;
    final ctrl = TextEditingController(
        text: add ? '' : (m.stock == null ? '' : formatQuantity(m.stock!)));
    final value = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(add ? 'Adicionar ao estoque' : 'Reinformar estoque atual'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: add ? 'Quantidade comprada' : 'Quantidade atual',
            suffixText: m.form.toLowerCase(),
            helperText: 'Ex.: 30, 14 1/2, 7,5',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, parseQuantity(ctrl.text)),
              child: const Text('Salvar')),
        ],
      ),
    );
    if (value == null) return;
    if (add) {
      await AppDatabase.instance.addStock(m.id!, value);
    } else {
      await AppDatabase.instance.setStock(m.id!, value);
    }
    AppEvents.changed();
  }

  @override
  Widget build(BuildContext context) {
    final m = _med;
    if (m == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(m.name),
        actions: [
          IconButton(
            tooltip: 'Editar',
            icon: const Icon(Icons.edit),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => MedicationFormScreen(medication: m))),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: Color(m.color),
                child: const Icon(Icons.medication, color: Colors.white),
              ),
              title: Text(m.displayName),
              subtitle: Text([
                if (m.activeIngredient.isNotEmpty)
                  'Princípio ativo: ${m.activeIngredient}',
                'Forma: ${m.form}',
                if (!m.active) 'Inativo (sem avisos)',
                if (m.notes.isNotEmpty) m.notes,
              ].join('\n')),
            ),
          ),
          const SizedBox(height: 16),
          Text('Horários', style: text.titleMedium),
          if (_schedules.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Nenhum horário configurado. Edite o medicamento '
                  'para adicionar.'),
            ),
          for (final s in _schedules)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(s.active ? Icons.alarm : Icons.alarm_off),
              title: Text(s.describe()),
              subtitle: Text([
                formatDoseQuantity(s.dose, m.form),
                'desde ${formatDate(s.startDate)}',
                if (s.endDate != null) 'até ${formatDate(s.endDate!)}',
                if (!s.active) 'pausado',
              ].join(' · ')),
            ),
          const SizedBox(height: 16),
          Text('Estoque', style: text.titleMedium),
          const SizedBox(height: 8),
          if (m.tracksStock)
            Text(
              '${formatDoseQuantity(m.stock!, m.form)}'
              '${m.isLowStock ? '  ⚠ estoque baixo' : ''}',
              style: text.headlineSmall?.copyWith(
                  color: m.isLowStock
                      ? Theme.of(context).colorScheme.error
                      : null),
            )
          else
            const Text('Estoque não controlado.'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => _editStock(add: false),
                icon: const Icon(Icons.edit_note),
                label: const Text('Reinformar'),
              ),
              OutlinedButton.icon(
                onPressed: () => _editStock(add: true),
                icon: const Icon(Icons.add_shopping_cart),
                label: const Text('Adicionar'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: Text('Últimas doses', style: text.titleMedium)),
              TextButton.icon(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => DoseFormScreen(medication: m))),
                icon: const Icon(Icons.add),
                label: const Text('Registrar'),
              ),
            ],
          ),
          if (_doses.isEmpty) const Text('Nenhuma dose registrada.'),
          for (final d in _doses)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                d.status == DoseStatus.taken ? Icons.check_circle : Icons.block,
                color: d.status == DoseStatus.taken ? Colors.green : null,
              ),
              title: Text(formatDateTime(d.takenAt)),
              subtitle: Text(d.status == DoseStatus.taken
                  ? formatDoseQuantity(d.quantity, m.form)
                  : 'Pulada'),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => DoseFormScreen(dose: d, medication: m))),
            ),
        ],
      ),
    );
  }
}
