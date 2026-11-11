import 'package:flutter/material.dart';

import 'app_controller.dart';
import 'config.dart';
import 'screens/home_screen.dart';
import 'screens/sessions_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/squad_screen.dart';
import 'services/session_store.dart';
import 'squad/squad_controller.dart';
import 'services/settings_store.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await SettingsStore.load();
  final controller = AppController(settings);
  await controller.init();
  final squad = SquadController(
    settings,
    directory: SessionStore.directory,
    profiles: controller.profiles,
    appVersion: appVersion,
  )..sport = settings.sport;
  runApp(LiveTrainingApp(controller: controller, squad: squad));
}

class LiveTrainingApp extends StatelessWidget {
  const LiveTrainingApp({super.key, required this.controller, this.squad});

  final AppController controller;

  /// Squad sessions (one phone, several sensors). The tab is hidden when null (tests, previews).
  final SquadController? squad;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Live Training',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      themeMode: ThemeMode.dark,
      home: _Shell(controller: controller, squad: squad),
    );
  }
}

class _Shell extends StatefulWidget {
  const _Shell({required this.controller, this.squad});

  final AppController controller;
  final SquadController? squad;

  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> {
  int _tab = 0;

  int get _settingsTab => widget.squad == null ? 2 : 3;

  void _go(int i) {
    setState(() => _tab = i);
    if (i == 1) widget.controller.refreshSessions();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: IndexedStack(
          index: _tab,
          children: [
            HomeScreen(controller: c, onOpenSettings: () => _go(_settingsTab)),
            SessionsScreen(controller: c),
            if (widget.squad != null) SquadScreen(squad: widget.squad!),
            SettingsScreen(controller: c),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: _go,
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.monitor_heart_outlined),
            selectedIcon: Icon(Icons.monitor_heart),
            label: 'LIVE',
          ),
          const NavigationDestination(icon: Icon(Icons.timeline_rounded), label: 'SESSIONS'),
          if (widget.squad != null) const NavigationDestination(icon: Icon(Icons.groups_rounded), label: 'SQUAD'),
          const NavigationDestination(icon: Icon(Icons.tune_rounded), label: 'SETTINGS'),
        ],
      ),
    );
  }
}
