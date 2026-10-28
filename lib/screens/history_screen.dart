import 'package:flutter/material.dart';

import '../app_events.dart';
import '../db.dart';
import '../main.dart';
import '../models.dart';
import 'dose_form_screen.dart';

/// Períodos do filtro do histórico; `days == null` = todos.
enum HistoryPeriod {
  week('7 dias', 7),
  month('30 dias', 30),
  quarter('90 dias', 90),
  year('1 ano', 365),
  all('Todos', null);

  const HistoryPeriod(this.label, this.days);
  final String label;
  final int? days;

  /// Início do período: meia-noite de (hoje - days + 1), incluindo hoje.
  DateTime? get from {
    if (days == null) return null;
    final today = dateOnly(DateTime.now());
    return DateTime(today.year, today.month, today.day - days! + 1);
  }
}

/// Histórico de doses registradas, com filtro por período e medicamento.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  static const _pageSize = 200;

  List<DoseRecord> _doses = [];
  Map<int, Medication> _meds = {};
  int? _filter;
  HistoryPeriod _period = HistoryPeriod.month;
  int _limit = _pageSize;

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
    final meds = {for (final m in await db.medications()) m.id!: m};
    final doses = await db.doses(
        medicationId: _filter, from: _period.from, limit: _limit);
    if (!mounted) return;
    setState(() {
      _meds = meds;
      _doses = doses;
    });
  }

  Future<void> _confirmDelete(DoseRecord d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir registro?'),
        content: Text('${_meds[d.medicationId]?.displayName ?? ''}\n'
            '${formatDateTime(d.takenAt)}'),
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
    if (ok == true) {
      await AppDatabase.instance.deleteDose(d);
      await AppEvents.dataChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    DateTime? lastDay;
    for (final d in _doses) {
      final day = dateOnly(d.takenAt);
      if (day != lastDay) {
        lastDay = day;
        children.add(Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(
            '${weekdayShort[day.weekday - 1]}, ${formatDate(day)}',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Theme.of(context).colorScheme.primary),
          ),
        ));
      }
      final m = _meds[d.medicationId];
      final taken = d.status == DoseStatus.taken;
      final late = d.scheduledAt == null
          ? null
          : d.takenAt.difference(d.scheduledAt!).inMinutes;
      children.add(ListTile(
        leading: Icon(taken ? Icons.check_circle : Icons.block,
            color: taken ? Colors.green : Theme.of(context).colorScheme.outline),
        title: Text(m?.displayName ?? 'Medicamento removido'),
        subtitle: Text([
          if (taken) '${formatHm(d.takenAt)} · '
              '${formatDoseQuantity(d.quantity, m?.form ?? 'un.')}'
          else 'Pulada',
          if (d.scheduledAt == null)
            'avulsa'
          else if (taken && late != null && late.abs() >= 5)
            'previsto ${formatHm(d.scheduledAt!)}',
          if (d.notes.isNotEmpty) d.notes,
        ].join(' · ')),
        trailing: PopupMenuButton<String>(
          onSelected: (v) {
            if (v == 'edit') {
              Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => DoseFormScreen(dose: d, medication: m)));
            } else {
              _confirmDelete(d);
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'edit', child: Text('Editar')),
            PopupMenuItem(value: 'delete', child: Text('Excluir')),
          ],
        ),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => DoseFormScreen(dose: d, medication: m))),
      ));
    }
    if (_doses.length >= _limit) {
      children.add(Padding(
        padding: const EdgeInsets.all(16),
        child: OutlinedButton(
          onPressed: () {
            _limit += _pageSize;
            _load();
          },
          child: const Text('Carregar mais'),
        ),
      ));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Histórico de doses'),
        actions: [
          PopupMenuButton<int?>(
            tooltip: 'Filtrar por medicamento',
            icon: Icon(_filter == null
                ? Icons.filter_list
                : Icons.filter_list_alt),
            initialValue: _filter,
            onSelected: (v) {
              _filter = v == -1 ? null : v;
              _limit = _pageSize;
              _load();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: -1, child: Text('Todos')),
              for (final m in _meds.values)
                PopupMenuItem(value: m.id, child: Text(m.displayName)),
            ],
          ),
          settingsAction(context),
        ],
      ),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                for (final p in HistoryPeriod.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(p.label),
                      selected: _period == p,
                      onSelected: (_) {
                        _period = p;
                        _limit = _pageSize;
                        _load();
                      },
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _doses.isEmpty
                ? Center(
                    child: Text(_period == HistoryPeriod.all
                        ? 'Nenhuma dose registrada.'
                        : 'Nenhuma dose registrada neste período.'))
                : ListView(
                    padding: const EdgeInsets.only(bottom: 88),
                    children: children),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: null,
        tooltip: 'Registrar dose',
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => DoseFormScreen(
                medication: _filter == null ? null : _meds[_filter]))),
        child: const Icon(Icons.add),
      ),
    );
  }
}
