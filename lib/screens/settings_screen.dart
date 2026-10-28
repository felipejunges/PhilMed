import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../app_events.dart';
import '../auto_backup.dart';
import '../db.dart';
import '../models.dart';
import '../notifications.dart';

/// Permissões de aviso e backup (exportar/importar o banco de dados).
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  ({bool notifications, bool exactAlarms})? _perm;
  bool _busy = false;
  bool _autoEnabled = true;
  String _autoDir = '';
  ({DateTime? last, String? error})? _autoResult;

  @override
  void initState() {
    super.initState();
    _refreshPerm();
    AutoBackup.status.addListener(_refreshAuto);
    _refreshAuto();
  }

  @override
  void dispose() {
    AutoBackup.status.removeListener(_refreshAuto);
    super.dispose();
  }

  Future<void> _refreshAuto() async {
    final enabled = await AutoBackup.isEnabled();
    final dir = (await AutoBackup.directory()).path;
    final result = await AutoBackup.lastResult();
    if (!mounted) return;
    setState(() {
      _autoEnabled = enabled;
      _autoDir = dir;
      _autoResult = result;
    });
  }

  String _autoSubtitle() {
    final r = _autoResult;
    final lines = [
      'Uma cópia por dia, atualizada a cada alteração, mantendo os últimos '
          '${AutoBackup.keepDays} dias. Fica preservada mesmo se o app for '
          'desinstalado.',
      'Pasta: $_autoDir',
      if (r?.last != null) 'Último backup: ${formatDateTime(r!.last!)}',
      if (r?.error != null) 'Erro no último backup: ${r!.error}',
    ];
    return lines.join('\n');
  }

  Future<void> _refreshPerm() async {
    final p = await NotificationService.permissionStatus();
    if (mounted) setState(() => _perm = p);
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final bytes = await AppDatabase.instance.exportBytes();
      final now = DateTime.now();
      final name = 'philmed-${now.year}${two(now.month)}${two(now.day)}-'
          '${two(now.hour)}${two(now.minute)}.db';
      final uri = await FilePicker.saveFile(
        dialogTitle: 'Salvar backup',
        fileName: name,
        bytes: bytes,
      );
      if (uri != null) _snack('Backup salvo.');
    } catch (e) {
      _snack('Falha ao exportar: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Importar backup?'),
        content: const Text('Todos os dados atuais serão SUBSTITUÍDOS pelos '
            'do arquivo escolhido. Considere exportar um backup antes.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Escolher arquivo')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      final file = await FilePicker.pickFile(dialogTitle: 'Escolher backup');
      if (file == null) return;
      final bytes = await file.readAsBytes();
      final tmp = File(p.join(
          (await getTemporaryDirectory()).path, 'philmed-import.db'));
      await tmp.writeAsBytes(bytes, flush: true);
      // Guarda os dados atuais antes de substituí-los.
      await AutoBackup.run(tag: 'antes-importar');
      await AppDatabase.instance.importFrom(tmp.path);
      await tmp.delete();
      await AppEvents.dataChanged();
      _snack('Backup importado.');
    } catch (e) {
      _snack('Falha ao importar: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final perm = _perm;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Configurações')),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          children: [
            if (_busy) const LinearProgressIndicator(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Text('Avisos', style: text.titleMedium),
            ),
            if (Platform.isAndroid && perm != null) ...[
              ListTile(
                leading: Icon(perm.notifications
                    ? Icons.notifications_active
                    : Icons.notifications_off),
                title: const Text('Permissão de notificações'),
                subtitle: Text(perm.notifications ? 'Concedida' : 'Negada'),
              ),
              ListTile(
                leading: Icon(
                    perm.exactAlarms ? Icons.alarm_on : Icons.alarm_off),
                title: const Text('Alarmes no horário exato'),
                subtitle: Text(perm.exactAlarms
                    ? 'Concedida'
                    : 'Negada: os avisos podem atrasar alguns minutos'),
              ),
              if (!perm.notifications || !perm.exactAlarms)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: FilledButton(
                    onPressed: () async {
                      await NotificationService.requestPermissions();
                      await _refreshPerm();
                      await NotificationService.rescheduleAll();
                    },
                    child: const Text('Conceder permissões'),
                  ),
                ),
              const ListTile(
                leading: Icon(Icons.battery_alert),
                title: Text('Dica'),
                subtitle: Text('Em alguns aparelhos (Xiaomi, Samsung, '
                    'Motorola...), desative a otimização de bateria do '
                    'PhilMed para que os avisos não sejam bloqueados.'),
              ),
            ],
            if (Platform.isLinux)
              const ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('Linux'),
                subtitle: Text('No Linux os avisos só são exibidos enquanto '
                    'o app estiver aberto.'),
              ),
            ListTile(
              leading: const Icon(Icons.notifications),
              title: const Text('Enviar aviso de teste'),
              onTap: NotificationService.showTest,
            ),
            ListTile(
              leading: const Icon(Icons.refresh),
              title: const Text('Reagendar todos os avisos'),
              onTap: () async {
                await NotificationService.rescheduleAll();
                _snack('Avisos reagendados.');
              },
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text('Backup', style: text.titleMedium),
            ),
            SwitchListTile(
              secondary: Icon(_autoResult?.error == null
                  ? Icons.backup_outlined
                  : Icons.sync_problem),
              title: const Text('Backup automático'),
              subtitle: Text(_autoSubtitle()),
              isThreeLine: true,
              value: _autoEnabled,
              onChanged: (v) => AutoBackup.setEnabled(v),
            ),
            if (_autoEnabled)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await AutoBackup.run();
                    final r = await AutoBackup.lastResult();
                    _snack(r.error == null
                        ? 'Backup feito.'
                        : 'Falha no backup: ${r.error}');
                  },
                  icon: const Icon(Icons.backup),
                  label: const Text('Fazer backup agora'),
                ),
              ),
            ListTile(
              leading: const Icon(Icons.upload_file),
              title: const Text('Exportar banco de dados'),
              subtitle: const Text('Salva um arquivo .db com todos os dados '
                  'onde você escolher'),
              onTap: _export,
            ),
            ListTile(
              leading: const Icon(Icons.download),
              title: const Text('Importar banco de dados'),
              subtitle: const Text('Substitui os dados atuais por um backup '
                  '(manual ou automático, na pasta Download/PhilMed)'),
              onTap: _import,
            ),
          ],
        ),
      ),
    );
  }
}
