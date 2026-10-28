import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'auto_backup.dart';
import 'db.dart';
import 'models.dart';
import 'scheduler.dart';

/// Nome da porta usada pelo isolate de segundo plano para avisar a UI de que
/// os dados mudaram.
const uiPortName = 'philmed_ui_port';

/// Opções de adiamento, em minutos.
const snoozeOptions = [5, 15, 30, 60];

const _channelId = 'doses';
const _channelName = 'Horário dos remédios';

/// Quantos dias à frente os avisos são agendados no Android.
const _scheduleWindow = Duration(days: 14);
const _maxScheduled = 400;

final FlutterLocalNotificationsPlugin _plugin =
    FlutterLocalNotificationsPlugin();

bool get _isAndroid => !kIsWeb && Platform.isAndroid;
bool get _isLinux => !kIsWeb && Platform.isLinux;

/// ID determinístico do aviso de uma ocorrência (ou do seu adiamento).
int notificationId(int scheduleId, DateTime at, {bool snooze = false}) {
  final s = '${snooze ? 'z' : 's'}$scheduleId@${at.millisecondsSinceEpoch}';
  // FNV-1a 31 bits.
  var h = 0x811c9dc5;
  for (final c in s.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xFFFFFFFF;
  }
  return h & 0x7FFFFFFF;
}

/// Identifica uma ocorrência a partir do payload do aviso.
class OccurrenceRef {
  OccurrenceRef(this.scheduleId, this.at);
  final int scheduleId;
  final DateTime at;

  String encode() =>
      jsonEncode({'s': scheduleId, 't': at.millisecondsSinceEpoch});

  static OccurrenceRef? decode(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    try {
      final m = jsonDecode(payload) as Map<String, dynamic>;
      return OccurrenceRef(
          m['s'] as int, DateTime.fromMillisecondsSinceEpoch(m['t'] as int));
    } catch (_) {
      return null;
    }
  }
}

Future<void> _initTimezone() async {
  tzdata.initializeTimeZones();
  try {
    final info = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(info.identifier));
  } catch (_) {
    // Mantém UTC se não for possível descobrir o fuso; os horários serão
    // convertidos a partir do instante absoluto de qualquer forma.
  }
}

// ---------------------------------------------------------------------------
// Ações sobre ocorrências (usadas pela UI e pelos avisos)

/// Registra a dose como tomada agora (ou em [takenAt]).
Future<void> markTaken(OccurrenceRef ref,
    {DateTime? takenAt, double? quantity}) async {
  final db = AppDatabase.instance;
  final s = await db.schedule(ref.scheduleId);
  if (s == null) return;
  final existing = await db.doseForOccurrence(ref.scheduleId, ref.at);
  final dose = existing ??
      DoseRecord(
        medicationId: s.medicationId,
        scheduleId: s.id,
        scheduledAt: ref.at,
        takenAt: DateTime.now(),
      );
  dose
    ..status = DoseStatus.taken
    ..takenAt = takenAt ?? DateTime.now()
    ..quantity = quantity ?? s.dose;
  await db.saveDose(dose);
  await clearOccurrenceNotifications(ref);
}

/// Registra a dose prevista como pulada.
Future<void> markSkipped(OccurrenceRef ref) async {
  final db = AppDatabase.instance;
  final s = await db.schedule(ref.scheduleId);
  if (s == null) return;
  final existing = await db.doseForOccurrence(ref.scheduleId, ref.at);
  final dose = existing ??
      DoseRecord(
        medicationId: s.medicationId,
        scheduleId: s.id,
        scheduledAt: ref.at,
        takenAt: DateTime.now(),
      );
  dose
    ..status = DoseStatus.skipped
    ..quantity = s.dose;
  await db.saveDose(dose);
  await clearOccurrenceNotifications(ref);
}

/// Adia o aviso da ocorrência em [minutes] minutos.
Future<void> snoozeOccurrence(OccurrenceRef ref, int minutes) async {
  final until = DateTime.now().add(Duration(minutes: minutes));
  await AppDatabase.instance.saveSnooze(
      Snooze(scheduleId: ref.scheduleId, scheduledAt: ref.at, until: until));
  await _plugin.cancel(id: notificationId(ref.scheduleId, ref.at));
  await _plugin.cancel(id: notificationId(ref.scheduleId, ref.at, snooze: true));
  if (_isAndroid) {
    final s = await AppDatabase.instance.schedule(ref.scheduleId);
    final m = s == null
        ? null
        : await AppDatabase.instance.medication(s.medicationId);
    if (s != null && m != null) {
      await _scheduleAndroid(m, s, ref.at, until, snoozed: true);
    }
  }
}

Future<void> clearOccurrenceNotifications(OccurrenceRef ref) async {
  await _plugin.cancel(id: notificationId(ref.scheduleId, ref.at));
  await _plugin.cancel(id: notificationId(ref.scheduleId, ref.at, snooze: true));
}

/// Trata a resposta a um aviso (botão "Tomei", "Adiar"...). Retorna `true`
/// se a ação foi totalmente tratada; `false` se o app deve abrir a ocorrência.
Future<bool> _handleAction(NotificationResponse r) async {
  final ref = OccurrenceRef.decode(r.payload);
  if (ref == null) return true;
  final action = r.actionId;
  if (action == null || action.isEmpty) return false;
  if (action == 'take') {
    await markTaken(ref);
  } else if (action == 'skip') {
    await markSkipped(ref);
  } else if (action.startsWith('snooze')) {
    var minutes = int.tryParse(action.split(':').last);
    minutes ??= int.tryParse(
        RegExp(r'\d+').firstMatch(r.input ?? '')?.group(0) ?? '');
    await snoozeOccurrence(ref, minutes ?? 15);
  } else {
    return false;
  }
  return true;
}

/// Chamado pelo Android quando um botão do aviso é tocado com o app fechado.
@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  await _initTimezone();
  await _handleAction(response);
  await NotificationService.rescheduleAll();
  await AutoBackup.run();
  IsolateNameServer.lookupPortByName(uiPortName)?.send('changed');
}

// ---------------------------------------------------------------------------

class NotificationService {
  /// Ocorrência que o usuário pediu para abrir tocando no aviso.
  static final ValueNotifier<OccurrenceRef?> openRequest = ValueNotifier(null);

  /// Disparado quando dados mudam por causa de um aviso.
  static final ValueNotifier<int> changes = ValueNotifier(0);

  static Timer? _linuxTicker;
  static DateTime _linuxLastCheck = DateTime.now();

  static Future<void> init() async {
    await _initTimezone();
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('ic_notification'),
      linux: LinuxInitializationSettings(defaultActionName: 'Abrir'),
    );
    await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: _onForegroundResponse,
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );

    if (_isAndroid) {
      final details = await _plugin.getNotificationAppLaunchDetails();
      if (details?.didNotificationLaunchApp ?? false) {
        final r = details!.notificationResponse;
        if (r != null) await _onForegroundResponse(r);
      }
    }

    final port = ReceivePort();
    IsolateNameServer.removePortNameMapping(uiPortName);
    IsolateNameServer.registerPortWithName(port.sendPort, uiPortName);
    port.listen((_) => changes.value++);

    if (_isLinux) {
      _linuxLastCheck = DateTime.now();
      _linuxTicker =
          Timer.periodic(const Duration(seconds: 20), (_) => _linuxTick());
    }
  }

  static Future<void> _onForegroundResponse(NotificationResponse r) async {
    final handled = await _handleAction(r);
    if (handled) {
      await rescheduleAll();
      changes.value++;
    } else {
      openRequest.value = OccurrenceRef.decode(r.payload);
    }
  }

  /// Pede as permissões necessárias (avisos e alarmes exatos).
  static Future<void> requestPermissions() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return;
    await android.requestNotificationsPermission();
    final exact = await android.canScheduleExactNotifications() ?? true;
    if (!exact) await android.requestExactAlarmsPermission();
  }

  static Future<({bool notifications, bool exactAlarms})>
      permissionStatus() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return (notifications: true, exactAlarms: true);
    return (
      notifications: await android.areNotificationsEnabled() ?? false,
      exactAlarms: await android.canScheduleExactNotifications() ?? false,
    );
  }

  static Future<void> _pending = Future.value();

  /// Reagenda todos os avisos futuros a partir do banco de dados.
  static Future<void> rescheduleAll() {
    if (!_isAndroid) return Future.value();
    return _pending = _pending.catchError((_) {}).then((_) => _reschedule());
  }

  static Future<void> _reschedule() async {
    final db = AppDatabase.instance;
    await db.purgeOldSnoozes();
    final now = DateTime.now();
    final agenda = await buildAgenda(now, now.add(_scheduleWindow));
    final snoozes = await db.snoozes();

    await _plugin.cancelAllPendingNotifications();
    final exact = await _canScheduleExact();

    var count = 0;
    for (final s in snoozes) {
      if (!s.until.isAfter(now)) continue;
      if (await db.doseForOccurrence(s.scheduleId, s.scheduledAt) != null) {
        continue;
      }
      final sch = await db.schedule(s.scheduleId);
      final med = sch == null ? null : await db.medication(sch.medicationId);
      if (sch == null || med == null || !med.active) continue;
      await _scheduleAndroid(med, sch, s.scheduledAt, s.until,
          snoozed: true, exact: exact);
      count++;
    }
    for (final o in agenda) {
      if (count >= _maxScheduled) break;
      if (o.isDone || o.snooze != null) continue;
      await _scheduleAndroid(o.medication, o.schedule, o.at, o.at,
          exact: exact);
      count++;
    }
  }

  static Future<void> showTest() async {
    await _plugin.show(
      id: 1,
      title: 'PhilMed',
      body: 'Os avisos estão funcionando.',
      notificationDetails: _details(withActions: false),
    );
  }

  /// No Linux não há agendamento pelo sistema: enquanto o app estiver aberto,
  /// verifica periodicamente se há doses a avisar.
  static Future<void> _linuxTick() async {
    final now = DateTime.now();
    final from = _linuxLastCheck;
    _linuxLastCheck = now;
    final agenda = await buildAgenda(from, now);
    for (final o in agenda) {
      if (o.isDone || o.snooze != null) continue;
      await _showNow(o.medication, o.schedule, o.at);
    }
    for (final s in await AppDatabase.instance.snoozes()) {
      if (s.until.isAfter(from) && !s.until.isAfter(now)) {
        final db = AppDatabase.instance;
        if (await db.doseForOccurrence(s.scheduleId, s.scheduledAt) != null) {
          continue;
        }
        final sch = await db.schedule(s.scheduleId);
        final med = sch == null ? null : await db.medication(sch.medicationId);
        if (sch != null && med != null) {
          await _showNow(med, sch, s.scheduledAt, snoozed: true);
        }
      }
    }
  }

  static void dispose() => _linuxTicker?.cancel();
}

String _title(Medication m) => 'Hora do remédio: ${m.displayName}';

String _body(Medication m, Schedule s, DateTime at, bool snoozed) {
  final qty = formatDoseQuantity(s.dose, m.form);
  return 'Tomar $qty · previsto para ${formatHm(at)}${snoozed ? ' (adiado)' : ''}';
}

Future<bool> _canScheduleExact() async =>
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.canScheduleExactNotifications() ??
    false;

NotificationDetails _details({bool withActions = true}) {
  return NotificationDetails(
    android: AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: 'Avisos na hora de tomar cada medicamento',
      importance: Importance.max,
      priority: Priority.high,
      category: AndroidNotificationCategory.reminder,
      visibility: NotificationVisibility.public,
      ticker: 'Hora do remédio',
      actions: withActions
          ? const [
              AndroidNotificationAction('take', 'Tomei',
                  cancelNotification: true),
              AndroidNotificationAction('snooze:15', 'Adiar 15 min',
                  cancelNotification: true),
              AndroidNotificationAction(
                'snooze',
                'Adiar…',
                cancelNotification: true,
                inputs: [
                  AndroidNotificationActionInput(
                    choices: ['5 min', '15 min', '30 min', '60 min'],
                    allowFreeFormInput: false,
                    label: 'Adiar por',
                  ),
                ],
              ),
            ]
          : null,
    ),
    linux: LinuxNotificationDetails(
      urgency: LinuxNotificationUrgency.critical,
      category: LinuxNotificationCategory.imReceived,
      actions: withActions
          ? [
              const LinuxNotificationAction(key: 'take', label: 'Tomei'),
              for (final m in snoozeOptions)
                LinuxNotificationAction(key: 'snooze:$m', label: '+$m min'),
            ]
          : const [],
    ),
  );
}

Future<void> _scheduleAndroid(
    Medication m, Schedule s, DateTime occurrence, DateTime fireAt,
    {bool snoozed = false, bool? exact}) async {
  if (!fireAt.isAfter(DateTime.now())) return;
  exact ??= await _canScheduleExact();
  await _plugin.zonedSchedule(
    id: notificationId(s.id!, occurrence, snooze: snoozed),
    title: _title(m),
    body: _body(m, s, occurrence, snoozed),
    scheduledDate: tz.TZDateTime.from(fireAt, tz.local),
    notificationDetails: _details(),
    androidScheduleMode: exact
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle,
    payload: OccurrenceRef(s.id!, occurrence).encode(),
  );
}

Future<void> _showNow(Medication m, Schedule s, DateTime occurrence,
    {bool snoozed = false}) async {
  await _plugin.show(
    id: notificationId(s.id!, occurrence, snooze: snoozed),
    title: _title(m),
    body: _body(m, s, occurrence, snoozed),
    notificationDetails: _details(),
    payload: OccurrenceRef(s.id!, occurrence).encode(),
  );
}
