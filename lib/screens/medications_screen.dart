import 'package:flutter/material.dart';

import '../app_events.dart';
import '../db.dart';
import '../main.dart';
import '../models.dart';
import 'medication_detail_screen.dart';
import 'medication_form_screen.dart';

class MedicationsScreen extends StatefulWidget {
  const MedicationsScreen({super.key});

  @override
  State<MedicationsScreen> createState() => _MedicationsScreenState();
}

class _MedicationsScreenState extends State<MedicationsScreen> {
  List<Medication> _meds = [];
  Map<int, List<Schedule>> _schedules = {};

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
    final meds = await db.medications();
    final schedules = <int, List<Schedule>>{};
    for (final s in await db.schedules()) {
      schedules.putIfAbsent(s.medicationId, () => []).add(s);
    }
    if (!mounted) return;
    setState(() {
      _meds = meds;
      _schedules = schedules;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Medicamentos'),
        actions: [settingsAction(context)],
      ),
      body: _meds.isEmpty
          ? const Center(
              child: Padding(
              padding: EdgeInsets.all(32),
              child: Text('Nenhum medicamento cadastrado.\n'
                  'Toque em "Novo" para começar.',
                  textAlign: TextAlign.center),
            ))
          : ListView.separated(
              padding: const EdgeInsets.only(bottom: 88),
              itemCount: _meds.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final m = _meds[i];
                final sch =
                    (_schedules[m.id] ?? []).where((s) => s.active).toList();
                final lines = <String>[
                  if (m.activeIngredient.isNotEmpty) m.activeIngredient,
                  if (sch.isEmpty) 'Sem horários' else
                    ...sch.map((s) => s.describe()),
                  if (m.tracksStock)
                    'Estoque: ${formatDoseQuantity(m.stock!, m.form)}',
                ];
                return ListTile(
                  enabled: true,
                  leading: CircleAvatar(
                    backgroundColor: Color(m.color),
                    child: const Icon(Icons.medication, color: Colors.white),
                  ),
                  title: Text(m.displayName +
                      (m.active ? '' : ' (inativo)')),
                  subtitle: Text(lines.join('\n')),
                  isThreeLine: lines.length > 1,
                  trailing: m.isLowStock
                      ? Icon(Icons.warning_amber,
                          color: Theme.of(context).colorScheme.error)
                      : null,
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => MedicationDetailScreen(m.id!))),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => const MedicationFormScreen())),
        icon: const Icon(Icons.add),
        label: const Text('Novo'),
      ),
    );
  }
}
