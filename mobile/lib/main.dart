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
    final items = [
      (Icons.wb_twilight_rounded, 'Today'),
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
      // Floating bar with the record button raised in the middle.
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(14, 0, 14, 10),
        child: SizedBox(
          height: 84,
          child: Stack(
            alignment: Alignment.bottomCenter,
            children: [
              Container(
                height: 64,
                decoration: BoxDecoration(
                  color: AppColors.surfaceHigh.withValues(alpha: 0.97),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppColors.outline, width: 0.6),
                  boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 18, offset: Offset(0, 6))],
                ),
                child: Row(
                  children: [
                    // Two equal halves around the record button, so it sits in the middle.
                    for (final half in [
                      [for (var i = 0; i < (items.length + 1) ~/ 2; i++) i],
                      [for (var i = (items.length + 1) ~/ 2; i < items.length; i++) i],
                    ]) ...[
                      Expanded(
                        child: Row(
                          children: [
                            for (final i in half)
                              Expanded(
                                child: _NavItem(
                                  icon: items[i].$1,
                                  label: items[i].$2,
                                  selected: i == _tab,
                                  onTap: () => _go(i),
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (half.isNotEmpty && half.first == 0) const SizedBox(width: 80),
                    ],
                  ],
                ),
              ),
              Positioned(
                top: 0,
                child: ListenableBuilder(
                  listenable: c,
                  builder: (context, _) => _RecordButton(
                    recording: c.isRecording,
                    onTap: () {
                      if (c.isRecording) {
                        _go(0);
                      } else {
                        showStartSheet(context, c);
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.icon, required this.label, required this.selected, required this.onTap});

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: 34,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 24, color: selected ? AppColors.brand : AppColors.textFaint),
          const SizedBox(height: 3),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.clip,
            style: TextStyle(
              fontSize: 11,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? AppColors.text : AppColors.textFaint,
            ),
          ),
        ],
      ),
    );
  }
}

/// Start a session (lime) or, while recording, go back to it (red).
class _RecordButton extends StatelessWidget {
  const _RecordButton({required this.recording, required this.onTap});

  final bool recording;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = recording ? AppColors.danger : AppColors.brand;
    return Tooltip(
      message: recording ? 'Back to the session' : 'Start a session',
      child: Material(
        color: color,
        shape: const CircleBorder(side: BorderSide(color: AppColors.background, width: 5)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox.square(
            dimension: 70,
            child: Icon(
              recording ? Icons.stop_rounded : Icons.add_rounded,
              size: 36,
              color: recording ? AppColors.text : AppColors.onBrand,
            ),
          ),
        ),
      ),
    );
  }
}
