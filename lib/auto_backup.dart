import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'db.dart';
import 'models.dart';

/// Backup automático: grava uma cópia do banco numa pasta pública
/// (Download/PhilMed no Android), que sobrevive à desinstalação do app.
///
/// Mantém um arquivo por dia (`philmed-auto-AAAAMMDD.db`), sobrescrito a cada
/// alteração, e guarda os últimos [keepDays] dias.
class AutoBackup {
  static const keepDays = 7;
  static const _debounce = Duration(seconds: 5);
  static const _keyEnabled = 'auto_backup_enabled';
  static const _keyLast = 'auto_backup_last';
  static const _keyError = 'auto_backup_error';
  static final _autoName = RegExp(r'^philmed-auto-\d{8}(-\d+)?\.db$');

  /// Muda quando um backup termina (para a tela de configurações).
  static final ValueNotifier<int> status = ValueNotifier(0);

  static Timer? _timer;
  static Future<void> _running = Future.value();

  static Future<Directory> directory() async {
    if (!kIsWeb && Platform.isAndroid) {
      return Directory('/storage/emulated/0/Download/PhilMed');
    }
    final downloads = await getDownloadsDirectory();
    if (downloads != null) return Directory(p.join(downloads.path, 'PhilMed'));
    return Directory(
        p.join((await getApplicationSupportDirectory()).path, 'backups'));
  }

  static Future<bool> isEnabled() async =>
      await AppDatabase.instance.getSetting(_keyEnabled) != '0';

  static Future<void> setEnabled(bool enabled) async {
    await AppDatabase.instance.setSetting(_keyEnabled, enabled ? '1' : '0');
    if (enabled) await run();
    status.value++;
  }

  static Future<({DateTime? last, String? error})> lastResult() async {
    final db = AppDatabase.instance;
    final last = int.tryParse(await db.getSetting(_keyLast) ?? '');
    return (
      last: last == null ? null : DateTime.fromMillisecondsSinceEpoch(last),
      error: await db.getSetting(_keyError),
    );
  }

  /// Agenda um backup para daqui a alguns segundos, agrupando alterações
  /// seguidas num único arquivo gravado.
  static void schedule() {
    _timer?.cancel();
    _timer = Timer(_debounce, () => run());
  }

  /// Faz o backup agora. [tag] gera um arquivo avulso, que não é apagado
  /// pela rotação (ex.: "antes-importar").
  static Future<void> run({String? tag}) {
    _timer?.cancel();
    return _running =
        _running.catchError((_) {}).then((_) => _run(tag: tag));
  }

  static Future<void> _run({String? tag}) async {
    final db = AppDatabase.instance;
    if (tag == null && !await isEnabled()) return;
    try {
      final dir = await directory();
      await dir.create(recursive: true);
      final now = DateTime.now();
      final day = '${now.year}${two(now.month)}${two(now.day)}';
      final base = tag == null
          ? 'philmed-auto-$day'
          : 'philmed-$tag-$day-${two(now.hour)}${two(now.minute)}';
      final bytes = await db.exportBytes();
      await _write(dir, base, bytes);
      if (tag == null) await _prune(dir);
      await db.setSetting(_keyLast, '${now.millisecondsSinceEpoch}');
      await db.setSetting(_keyError, null);
    } catch (e) {
      await db.setSetting(_keyError, e.toString());
    }
    status.value++;
  }

  /// Grava de forma atômica (arquivo temporário + rename). Se o arquivo do
  /// dia pertencer a uma instalação anterior do app, o Android não deixa
  /// sobrescrevê-lo; nesse caso usa um nome alternativo (-1, -2...).
  static Future<void> _write(Directory dir, String base, Uint8List bytes) async {
    Object? lastError;
    for (var i = 0; i < 10; i++) {
      final name = i == 0 ? '$base.db' : '$base-$i.db';
      final target = File(p.join(dir.path, name));
      final tmp = File('${target.path}.tmp');
      try {
        await tmp.writeAsBytes(bytes, flush: true);
        await tmp.rename(target.path);
        return;
      } on FileSystemException catch (e) {
        lastError = e;
        try {
          if (await tmp.exists()) await tmp.delete();
        } catch (_) {}
      }
    }
    throw lastError ?? const FileSystemException('Falha ao gravar o backup');
  }

  /// Apaga backups automáticos de dias anteriores ao período mantido.
  static Future<void> _prune(Directory dir) async {
    final limit = dateOnly(DateTime.now())
        .subtract(const Duration(days: keepDays - 1));
    final limitStr = '${limit.year}${two(limit.month)}${two(limit.day)}';
    await for (final f in dir.list()) {
      final name = p.basename(f.path);
      if (f is! File || !_autoName.hasMatch(name)) continue;
      final day = name.substring('philmed-auto-'.length,
          'philmed-auto-'.length + 8);
      if (day.compareTo(limitStr) < 0) {
        try {
          await f.delete();
        } catch (_) {
          // Arquivo de outra instalação: o Android não deixa apagar.
        }
      }
    }
  }
}
