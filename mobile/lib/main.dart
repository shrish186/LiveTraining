import 'package:flutter/material.dart';

import 'app_controller.dart';
import 'screens/home_screen.dart';
import 'screens/sessions_screen.dart';
import 'screens/settings_screen.dart';
import 'services/settings_store.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = AppController(await SettingsStore.load());
  await controller.init();
  runApp(LiveTrainingApp(controller: controller));
}

class LiveTrainingApp extends StatelessWidget {
  const LiveTrainingApp({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Live Training',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      themeMode: ThemeMode.dark,
      home: _Shell(controller: controller),
    );
  }
}

class _Shell extends StatefulWidget {
  const _Shell({required this.controller});

  final AppController controller;

  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> {
  int _tab = 0;

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
            HomeScreen(controller: c, onOpenSettings: () => _go(2)),
            SessionsScreen(controller: c),
            SettingsScreen(controller: c),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: _go,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.monitor_heart_outlined),
            selectedIcon: Icon(Icons.monitor_heart),
            label: 'LIVE',
          ),
          NavigationDestination(icon: Icon(Icons.timeline_rounded), label: 'SESSIONS'),
          NavigationDestination(icon: Icon(Icons.tune_rounded), label: 'SETTINGS'),
        ],
      ),
    );
  }
}
