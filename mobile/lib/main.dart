import 'package:flutter/material.dart';

import 'app_controller.dart';
import 'screens/home_screen.dart';
import 'screens/sessions_screen.dart';
import 'screens/settings_screen.dart';
import 'services/settings_store.dart';

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
    ThemeData theme(Brightness b) =>
        ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0B7285), brightness: b));
    return MaterialApp(
      title: 'Live Training',
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
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
  static const _titles = ['Live Training', 'Sessions', 'Settings'];

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Scaffold(
      appBar: AppBar(title: Text(_titles[_tab])),
      body: SafeArea(
        child: IndexedStack(index: _tab, children: [
          HomeScreen(controller: c),
          SessionsScreen(controller: c),
          SettingsScreen(controller: c),
        ]),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) {
          setState(() => _tab = i);
          if (i == 1) c.refreshSessions();
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.monitor_heart), label: 'Live'),
          NavigationDestination(icon: Icon(Icons.list), label: 'Sessions'),
          NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}
