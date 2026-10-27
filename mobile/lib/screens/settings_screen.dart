import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_controller.dart';
import '../config.dart';
import '../services/backend_api.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

enum _Check { untested, checking, ok, failed }

class _SettingsScreenState extends State<SettingsScreen> {
  late final _url = TextEditingController(text: widget.controller.settings.backendUrl);
  late final _athlete = TextEditingController(text: widget.controller.settings.athleteId?.toString() ?? '');
  _Check _check = _Check.untested;
  String? _error;

  AppController get c => widget.controller;

  /// Fields save as you type; recovery refreshes when you leave a field or test.
  void _saveFields() {
    c.settings.backendUrl = _url.text;
    c.settings.athleteId = int.tryParse(_athlete.text.trim());
  }

  Future<void> _test() async {
    FocusScope.of(context).unfocus();
    _saveFields();
    setState(() {
      _check = _Check.checking;
      _error = null;
    });
    try {
      await BackendApi(c.settings.backendUrl).health();
      setState(() => _check = _Check.ok);
      c.refreshRecovery();
    } on BackendException catch (e) {
      setState(() {
        _check = _Check.failed;
        _error = e.message;
      });
    }
  }

  Future<void> _connectWhoop() async {
    _saveFields();
    final uri = Uri.parse('${c.settings.backendUrl}/auth/whoop/login');
    final ok = c.settings.backendUrl.isNotEmpty && await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Set the backend URL first')));
    }
  }

  Future<void> _pickDefault(String title, List<String> options, String current, void Function(String) set) async {
    final v = await showOptionSheet(context, title: title, options: options, current: current);
    if (v != null) setState(() => set(v));
  }

  @override
  void dispose() {
    _url.dispose();
    _athlete.dispose();
    super.dispose();
  }

  String get _host => Uri.tryParse(c.settings.backendUrl)?.host ?? '';

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final s = c.settings;
        // A synced recovery proves the backend works even before anyone taps Test.
        final connected = _check == _Check.ok || (_check == _Check.untested && c.recovery != null);
        final (Color dot, String status) = switch (_check) {
          _Check.checking => (AppColors.warning, 'Checking…'),
          _Check.failed => (AppColors.danger, 'Can\'t reach the backend'),
          _ when connected => (AppColors.good, 'Connected to $_host'),
          _ => (AppColors.textFaint, s.backendUrl.isEmpty ? 'Not set up' : 'Not tested yet'),
        };
        final whoopOk = c.recovery != null;

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            const ScreenHeader(overline: 'Setup', title: 'Settings'),

            // ---- Connection ------------------------------------------------
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionLabel('Connection'),
                  const SizedBox(height: 12),
                  _StatusLine(color: dot, text: status),
                  const SizedBox(height: 18),
                  const _FieldLabel('Backend URL'),
                  TextField(
                    controller: _url,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    style: AppText.body,
                    decoration: const InputDecoration(hintText: 'http://172.20.10.2:8000'),
                    onChanged: (_) {
                      _saveFields();
                      if (_check != _Check.untested) setState(() => _check = _Check.untested);
                    },
                    onEditingComplete: () {
                      FocusScope.of(context).unfocus();
                      c.refreshRecovery();
                    },
                  ),
                  const SizedBox(height: 14),
                  const _FieldLabel('Athlete ID'),
                  TextField(
                    controller: _athlete,
                    keyboardType: TextInputType.number,
                    style: AppText.body,
                    decoration: const InputDecoration(hintText: '1'),
                    onChanged: (_) => _saveFields(),
                    onTapOutside: (_) {
                      FocusScope.of(context).unfocus();
                      c.refreshRecovery();
                    },
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _check == _Check.checking ? null : _test,
                      child: const FittedBox(child: Text('Test connection', maxLines: 1)),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.danger.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: SelectableText(_error!, style: AppText.dim.copyWith(color: AppColors.text)),
                    ),
                  ],
                  const SizedBox(height: 4),
                  const _Help(
                    title: 'How to connect',
                    body:
                        'On your Mac, run backend/run_dev.sh and type the "Backend URL for the app" it prints. '
                        'The iPhone and the Mac must be on the same network (your iPhone hotspot works). '
                        'Your Athlete ID is listed on the status page at http://localhost:8000.',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // ---- WHOOP -----------------------------------------------------
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionLabel('WHOOP'),
                  const SizedBox(height: 12),
                  _StatusLine(
                    color: whoopOk ? AppColors.good : AppColors.textFaint,
                    text: whoopOk ? 'Connected · recovery synced' : 'Not connected yet',
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _connectWhoop,
                      icon: const Icon(Icons.link_rounded),
                      label: FittedBox(child: Text(whoopOk ? 'Reconnect WHOOP' : 'Connect WHOOP', maxLines: 1)),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const _Help(
                    title: 'Doesn\'t finish on the phone?',
                    body:
                        'WHOOP sends you back to localhost, which only works on the Mac. Open '
                        'http://localhost:8000 on the Mac and click Connect WHOOP there instead.',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // ---- Defaults ----------------------------------------------------
            AppCard(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionLabel('Defaults for new sessions'),
                  const SizedBox(height: 6),
                  SettingRow(
                    icon: Icons.sports_rounded,
                    label: 'Sport',
                    value: s.sport,
                    onTap: () => _pickDefault('Sport', sportOptions, s.sport, (v) {
                      s.sport = v;
                      c.updateSetup(sport: v);
                    }),
                  ),
                  SettingRow(
                    icon: Icons.event_note_rounded,
                    label: 'Session type',
                    value: s.sessionType,
                    onTap: () => _pickDefault('Session type', sessionTypeOptions, s.sessionType, (v) {
                      s.sessionType = v;
                      c.updateSetup(sessionType: v);
                    }),
                  ),
                  SettingRow(
                    icon: Icons.accessibility_new_rounded,
                    label: 'Sensor on',
                    value: s.placement,
                    onTap: () => _pickDefault('Sensor placement', placementOptions, s.placement, (v) {
                      s.placement = v;
                      c.updateSetup(placement: v);
                    }),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const Center(child: Text('Live Training Intelligence $appVersion', style: AppText.dim)),
          ],
        );
      },
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.color, required this.text});

  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: AppText.body.copyWith(fontWeight: FontWeight.w600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 8),
    child: Text(text, style: AppText.dim.copyWith(fontWeight: FontWeight.w600)),
  );
}

/// Collapsed "?" row that expands to a short explanation.
class _Help extends StatelessWidget {
  const _Help({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 8),
        expandedAlignment: Alignment.centerLeft,
        iconColor: AppColors.textDim,
        collapsedIconColor: AppColors.textFaint,
        title: Row(
          children: [
            const Icon(Icons.help_outline_rounded, size: 16, color: AppColors.textFaint),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: AppText.dim, maxLines: 1, overflow: TextOverflow.ellipsis)),
          ],
        ),
        children: [Text(body, style: AppText.dim)],
      ),
    );
  }
}
