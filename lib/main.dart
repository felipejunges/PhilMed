import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_events.dart';
import 'auto_backup.dart';
import 'db.dart';
import 'notifications.dart';
import 'screens/history_screen.dart';
import 'screens/medications_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/today_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppDatabase.instance.db;
  await NotificationService.init();
  runApp(const PhilMedApp());
  // Não bloqueia a abertura do app.
  NotificationService.requestPermissions()
      .then((_) => NotificationService.rescheduleAll());
  AutoBackup.schedule();
}

class PhilMedApp extends StatelessWidget {
  const PhilMedApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF2E7D6B);
    return MaterialApp(
      title: 'PhilMed',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: seed),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme:
            ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark),
        useMaterial3: true,
      ),
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: const HomeShell(),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    NotificationService.changes.addListener(AppEvents.changed);
    NotificationService.openRequest.addListener(_openFromNotification);
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _openFromNotification());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    NotificationService.changes.removeListener(AppEvents.changed);
    NotificationService.openRequest.removeListener(_openFromNotification);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      AppEvents.changed();
      NotificationService.rescheduleAll();
    }
  }

  void _openFromNotification() {
    final ref = NotificationService.openRequest.value;
    if (ref == null || !mounted) return;
    NotificationService.openRequest.value = null;
    setState(() => _tab = 0);
    openOccurrenceSheet(context, ref);
  }

  @override
  Widget build(BuildContext context) {
    const pages = [TodayScreen(), MedicationsScreen(), HistoryScreen()];
    return Scaffold(
      body: IndexedStack(index: _tab, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.today_outlined),
              selectedIcon: Icon(Icons.today),
              label: 'Agenda'),
          NavigationDestination(
              icon: Icon(Icons.medication_outlined),
              selectedIcon: Icon(Icons.medication),
              label: 'Medicamentos'),
          NavigationDestination(
              icon: Icon(Icons.history),
              label: 'Histórico'),
        ],
      ),
    );
  }
}

/// Ação comum das AppBars: abrir as configurações.
Widget settingsAction(BuildContext context) => IconButton(
      tooltip: 'Configurações e backup',
      icon: const Icon(Icons.settings_outlined),
      onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const SettingsScreen())),
    );
