import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;

import 'models.dart';

/// Acesso ao banco SQLite do app.
class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();

  static const fileName = 'philmed.db';
  static const schemaVersion = 2;

  Database? _db;
  static bool _factoryReady = false;

  static void _ensureFactory() {
    if (_factoryReady) return;
    if (_isDesktop) {
      ffi.sqfliteFfiInit();
      databaseFactory = ffi.databaseFactoryFfi;
    }
    _factoryReady = true;
  }

  static bool get _isDesktop =>
      !kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS);

  Future<String> get path async {
    _ensureFactory();
    // No desktop, getDatabasesPath() aponta para a pasta de trabalho; usa o
    // diretório de dados do usuário (ex.: ~/.local/share/com.philmed.philmed).
    final dir = _isDesktop
        ? (await getApplicationSupportDirectory()).path
        : await getDatabasesPath();
    return p.join(dir, fileName);
  }

  Future<Database> get db async {
    if (_db != null && _db!.isOpen) return _db!;
    _db = await _open(await path);
    return _db!;
  }

  Future<Database> _open(String path) async {
    _ensureFactory();
    await Directory(p.dirname(path)).create(recursive: true);
    return openDatabase(
      path,
      version: schemaVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE medications (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            active_ingredient TEXT NOT NULL DEFAULT '',
            strength REAL,
            strength_unit TEXT NOT NULL DEFAULT 'mg',
            form TEXT NOT NULL DEFAULT 'Comprimido',
            notes TEXT NOT NULL DEFAULT '',
            stock REAL,
            low_stock_threshold REAL,
            active INTEGER NOT NULL DEFAULT 1,
            color INTEGER NOT NULL DEFAULT 0
          )''');
        await db.execute('''
          CREATE TABLE schedules (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            medication_id INTEGER NOT NULL REFERENCES medications(id) ON DELETE CASCADE,
            type TEXT NOT NULL,
            interval INTEGER NOT NULL DEFAULT 1,
            weekdays INTEGER NOT NULL DEFAULT 127,
            times TEXT NOT NULL,
            dose REAL NOT NULL DEFAULT 1,
            start_date INTEGER NOT NULL,
            end_date INTEGER,
            active INTEGER NOT NULL DEFAULT 1
          )''');
        await db.execute('''
          CREATE TABLE doses (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            medication_id INTEGER NOT NULL REFERENCES medications(id) ON DELETE CASCADE,
            schedule_id INTEGER REFERENCES schedules(id) ON DELETE SET NULL,
            scheduled_at INTEGER,
            taken_at INTEGER NOT NULL,
            quantity REAL NOT NULL DEFAULT 1,
            status TEXT NOT NULL DEFAULT 'taken',
            notes TEXT NOT NULL DEFAULT ''
          )''');
        await db.execute(
            'CREATE INDEX idx_doses_taken ON doses(taken_at)');
        await db.execute(
            'CREATE INDEX idx_doses_sched ON doses(schedule_id, scheduled_at)');
        await db.execute('''
          CREATE TABLE snoozes (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            schedule_id INTEGER NOT NULL REFERENCES schedules(id) ON DELETE CASCADE,
            scheduled_at INTEGER NOT NULL,
            until_at INTEGER NOT NULL,
            UNIQUE(schedule_id, scheduled_at)
          )''');
        await _createSettings(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) await _createSettings(db);
      },
    );
  }

  static Future<void> _createSettings(Database db) => db.execute('''
      CREATE TABLE IF NOT EXISTS settings (
        key TEXT PRIMARY KEY,
        value TEXT
      )''');

  // -------------------------------------------------------------------------
  // Configurações (chave/valor)

  Future<String?> getSetting(String key) async {
    final rows = await (await db)
        .query('settings', where: 'key = ?', whereArgs: [key]);
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  Future<void> setSetting(String key, String? value) async {
    await (await db).insert('settings', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  // -------------------------------------------------------------------------
  // Medicamentos

  Future<List<Medication>> medications({bool onlyActive = false}) async {
    final rows = await (await db).query(
      'medications',
      where: onlyActive ? 'active = 1' : null,
      orderBy: 'active DESC, name COLLATE NOCASE',
    );
    return rows.map(Medication.fromMap).toList();
  }

  Future<Medication?> medication(int id) async {
    final rows =
        await (await db).query('medications', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Medication.fromMap(rows.first);
  }

  Future<int> saveMedication(Medication m) async {
    final d = await db;
    if (m.id == null) {
      m.id = await d.insert('medications', m.toMap()..remove('id'));
    } else {
      await d.update('medications', m.toMap(),
          where: 'id = ?', whereArgs: [m.id]);
    }
    return m.id!;
  }

  Future<void> deleteMedication(int id) async {
    await (await db).delete('medications', where: 'id = ?', whereArgs: [id]);
  }

  /// Reinforma o estoque atual (null desativa o controle de estoque).
  Future<void> setStock(int medicationId, double? stock) async {
    await (await db).update('medications', {'stock': stock},
        where: 'id = ?', whereArgs: [medicationId]);
  }

  Future<void> addStock(int medicationId, double amount) async {
    await (await db).rawUpdate(
        'UPDATE medications SET stock = COALESCE(stock, 0) + ? WHERE id = ?',
        [amount, medicationId]);
  }

  // -------------------------------------------------------------------------
  // Agendamentos

  Future<List<Schedule>> schedules({int? medicationId}) async {
    final rows = await (await db).query(
      'schedules',
      where: medicationId == null ? null : 'medication_id = ?',
      whereArgs: medicationId == null ? null : [medicationId],
      orderBy: 'id',
    );
    return rows.map(Schedule.fromMap).toList();
  }

  Future<Schedule?> schedule(int id) async {
    final rows =
        await (await db).query('schedules', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Schedule.fromMap(rows.first);
  }

  Future<int> saveSchedule(Schedule s) async {
    final d = await db;
    if (s.id == null) {
      s.id = await d.insert('schedules', s.toMap()..remove('id'));
    } else {
      await d.update('schedules', s.toMap(),
          where: 'id = ?', whereArgs: [s.id]);
    }
    return s.id!;
  }

  Future<void> deleteSchedule(int id) async {
    await (await db).delete('schedules', where: 'id = ?', whereArgs: [id]);
  }

  // -------------------------------------------------------------------------
  // Doses

  Future<List<DoseRecord>> doses({
    int? medicationId,
    DateTime? from,
    DateTime? to,
    int? limit,
  }) async {
    final where = <String>[];
    final args = <Object>[];
    if (medicationId != null) {
      where.add('medication_id = ?');
      args.add(medicationId);
    }
    if (from != null) {
      where.add('COALESCE(scheduled_at, taken_at) >= ?');
      args.add(from.millisecondsSinceEpoch);
    }
    if (to != null) {
      where.add('COALESCE(scheduled_at, taken_at) < ?');
      args.add(to.millisecondsSinceEpoch);
    }
    final rows = await (await db).query(
      'doses',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args,
      orderBy: 'taken_at DESC',
      limit: limit,
    );
    return rows.map(DoseRecord.fromMap).toList();
  }

  /// Doses registradas para ocorrências previstas a partir de [from], como
  /// conjunto de chaves "scheduleId@millis".
  Future<Set<String>> recordedOccurrenceKeys(DateTime from) async {
    final rows = await (await db).query(
      'doses',
      columns: ['schedule_id', 'scheduled_at'],
      where: 'schedule_id IS NOT NULL AND scheduled_at >= ?',
      whereArgs: [from.millisecondsSinceEpoch],
    );
    return {
      for (final r in rows) occurrenceKey(r['schedule_id'] as int,
          DateTime.fromMillisecondsSinceEpoch(r['scheduled_at'] as int))
    };
  }

  Future<DoseRecord?> doseForOccurrence(int scheduleId, DateTime at) async {
    final rows = await (await db).query('doses',
        where: 'schedule_id = ? AND scheduled_at = ?',
        whereArgs: [scheduleId, at.millisecondsSinceEpoch]);
    return rows.isEmpty ? null : DoseRecord.fromMap(rows.first);
  }

  /// Insere ou atualiza uma dose, ajustando o estoque do medicamento.
  Future<int> saveDose(DoseRecord dose) async {
    final d = await db;
    return d.transaction((txn) async {
      if (dose.id != null) {
        final old = await txn
            .query('doses', where: 'id = ?', whereArgs: [dose.id]);
        if (old.isNotEmpty) {
          final o = DoseRecord.fromMap(old.first);
          await _adjustStock(txn, o.medicationId, o.stockUsage);
        }
        await txn.update('doses', dose.toMap(),
            where: 'id = ?', whereArgs: [dose.id]);
      } else {
        dose.id = await txn.insert('doses', dose.toMap()..remove('id'));
      }
      await _adjustStock(txn, dose.medicationId, -dose.stockUsage);
      if (dose.scheduleId != null && dose.scheduledAt != null) {
        await txn.delete('snoozes',
            where: 'schedule_id = ? AND scheduled_at = ?',
            whereArgs: [
              dose.scheduleId,
              dose.scheduledAt!.millisecondsSinceEpoch
            ]);
      }
      return dose.id!;
    });
  }

  /// Exclui uma dose devolvendo a quantidade ao estoque.
  Future<void> deleteDose(DoseRecord dose) async {
    final d = await db;
    await d.transaction((txn) async {
      await txn.delete('doses', where: 'id = ?', whereArgs: [dose.id]);
      await _adjustStock(txn, dose.medicationId, dose.stockUsage);
    });
  }

  Future<void> _adjustStock(
      DatabaseExecutor txn, int medicationId, double delta) async {
    if (delta == 0) return;
    await txn.rawUpdate(
        'UPDATE medications SET stock = MAX(stock + ?, 0) '
        'WHERE id = ? AND stock IS NOT NULL',
        [delta, medicationId]);
  }

  // -------------------------------------------------------------------------
  // Adiamentos

  Future<List<Snooze>> snoozes() async {
    final rows = await (await db).query('snoozes', orderBy: 'until_at');
    return rows.map(Snooze.fromMap).toList();
  }

  Future<void> saveSnooze(Snooze s) async {
    await (await db).insert('snoozes', s.toMap()..remove('id'),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> purgeOldSnoozes() async {
    final limit = DateTime.now().subtract(const Duration(days: 2));
    await (await db).delete('snoozes',
        where: 'until_at < ?', whereArgs: [limit.millisecondsSinceEpoch]);
  }

  // -------------------------------------------------------------------------
  // Backup

  /// Valida um arquivo de banco importado e substitui o banco atual por ele.
  Future<void> importFrom(String sourcePath) async {
    _ensureFactory();
    final probe = await openDatabase(sourcePath, readOnly: true,
        singleInstance: false);
    try {
      final tables = (await probe.rawQuery(
              "SELECT name FROM sqlite_master WHERE type = 'table'"))
          .map((r) => r['name'])
          .toSet();
      for (final t in ['medications', 'schedules', 'doses']) {
        if (!tables.contains(t)) {
          throw const FormatException(
              'O arquivo não é um backup válido do PhilMed.');
        }
      }
      final version =
          (await probe.rawQuery('PRAGMA user_version')).first.values.first;
      if (version is int && version > schemaVersion) {
        throw const FormatException(
            'O backup foi criado por uma versão mais nova do app.');
      }
    } finally {
      await probe.close();
    }

    final target = await path;
    await close();
    final backup = File('$target.bak');
    if (await File(target).exists()) await File(target).copy(backup.path);
    try {
      for (final suffix in ['-wal', '-shm', '-journal']) {
        final f = File('$target$suffix');
        if (await f.exists()) await f.delete();
      }
      await File(sourcePath).copy(target);
      await db; // reabre e aplica migrações, se houver
    } catch (_) {
      if (await backup.exists()) await backup.copy(target);
      rethrow;
    }
  }

  /// Retorna os bytes de uma cópia consistente do banco. A leitura acontece
  /// dentro de uma transação (BEGIN IMMEDIATE), que impede escritas de
  /// qualquer conexão enquanto o arquivo é copiado.
  Future<Uint8List> exportBytes() async {
    final target = await path;
    final d = await db;
    late Uint8List bytes;
    await d.transaction((txn) async {
      await txn.rawQuery('SELECT count(*) FROM medications');
      bytes = await File(target).readAsBytes();
    });
    return bytes;
  }
}

String occurrenceKey(int scheduleId, DateTime at) =>
    '$scheduleId@${at.millisecondsSinceEpoch}';
