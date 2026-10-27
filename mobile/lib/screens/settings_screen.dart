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

class _SettingsScreenState extends State<SettingsScreen> {
  late final _url = TextEditingController(text: widget.controller.settings.backendUrl);
  late final _athlete = TextEditingController(text: widget.controller.settings.athleteId?.toString() ?? '');
  String? _status;
  bool _statusOk = false;
  bool _checking = false;

  AppController get c => widget.controller;

  void _save({bool quiet = false}) {
    FocusScope.of(context).unfocus();
    c.settings.backendUrl = _url.text;
    c.settings.athleteId = int.tryParse(_athlete.text.trim());
    c.refreshRecovery();
    if (!quiet) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Saved'), duration: Duration(seconds: 1)));
    }
  }

  Future<void> _test() async {
    _save(quiet: true);
    setState(() {
      _checking = true;
      _status = null;
    });
    try {
      await BackendApi(c.settings.backendUrl).health();
      setState(() {
        _status = 'Connected to ${c.settings.backendUrl}';
        _statusOk = true;
      });
    } on BackendException catch (e) {
      setState(() {
        _status = e.message;
        _statusOk = false;
      });
    } finally {
      setState(() => _checking = false);
    }
  }

  Future<void> _connectWhoop() async {
    _save(quiet: true);
    final uri = Uri.parse('${c.settings.backendUrl}/auth/whoop/login');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      setState(() {
        _status = 'Could not open $uri';
        _statusOk = false;
      });
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

  @override
  Widget build(BuildContext context) {
    final s = c.settings;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        const ScreenHeader(overline: 'Setup', title: 'Settings'),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionLabel('Backend'),
              const SizedBox(height: 14),
              TextField(
                controller: _url,
                keyboardType: TextInputType.url,
                autocorrect: false,
                style: AppText.body,
                decoration: const InputDecoration(
                  labelText: 'Backend URL',
                  hintText: 'http://172.20.10.2:8000',
                  helperText: 'The "Backend URL for the app" that run_dev.sh prints on your Mac',
                ),
                onSubmitted: (_) => _save(),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _athlete,
                keyboardType: TextInputType.number,
                style: AppText.body,
                decoration: const InputDecoration(
                  labelText: 'Athlete ID',
                  hintText: '1',
                  helperText: 'Listed on the status page at http://localhost:8000 on your Mac',
                ),
                onSubmitted: (_) => _save(),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(onPressed: _save, child: const Text('Save')),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _checking ? null : _test,
                      child: _checking
                          ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Test connection'),
                    ),
                  ),
                ],
              ),
              if (_status != null) ...[
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: (_statusOk ? AppColors.good : AppColors.danger).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        _statusOk ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                        size: 18,
                        color: _statusOk ? AppColors.good : AppColors.danger,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: SelectableText(
                          _status!,
                          style: AppText.dim.copyWith(color: _statusOk ? AppColors.good : AppColors.text),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionLabel('WHOOP account'),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _connectWhoop,
                  icon: const Icon(Icons.link_rounded),
                  label: const Text('Connect WHOOP account'),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Easiest on the Mac: open http://localhost:8000 and click Connect WHOOP. The WHOOP redirect '
                'goes to localhost, so finishing on the phone only works if your WHOOP app is registered '
                'with the Mac\'s IP.',
                style: AppText.dim,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
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
  }
}
