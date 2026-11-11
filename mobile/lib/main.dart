import 'package:flutter/material.dart';

import 'app_controller.dart';
import 'config.dart';
import 'screens/home_screen.dart';
import 'screens/open_coach.dart';
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
    final items = [
      (Icons.insights_rounded, 'Today'),
      (Icons.timeline_rounded, 'Sessions'),
      if (widget.squad != null) (Icons.groups_rounded, 'Squad'),
      (Icons.tune_rounded, 'Settings'),
    ];
    return Scaffold(
      extendBody: true,
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
      // Floating bar with a round coach button beside it.
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(14, 0, 14, 10),
        child: Row(
          children: [
            Expanded(
              child: Container(
                height: 66,
                decoration: BoxDecoration(
                  color: AppColors.surfaceHigh.withValues(alpha: 0.96),
                  borderRadius: BorderRadius.circular(33),
                  boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 16, offset: Offset(0, 4))],
                ),
                child: Row(
                  children: [
                    for (var i = 0; i < items.length; i++)
                      Expanded(
                        child: InkResponse(
                          onTap: () => _go(i),
                          radius: 36,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(items[i].$1, size: 24, color: i == _tab ? AppColors.text : AppColors.textFaint),
                              const SizedBox(height: 3),
                              Text(
                                items[i].$2,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: i == _tab ? FontWeight.w700 : FontWeight.w500,
                                  color: i == _tab ? AppColors.text : AppColors.textFaint,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            Tooltip(
              message: 'Coach',
              child: Material(
                color: AppColors.surfaceHigh,
                shape: const CircleBorder(side: BorderSide(color: AppColors.load, width: 2)),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => openCoach(context, c),
                  child: const SizedBox.square(
                    dimension: 62,
                    child: Icon(Icons.auto_awesome_rounded, color: AppColors.load, size: 26),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
