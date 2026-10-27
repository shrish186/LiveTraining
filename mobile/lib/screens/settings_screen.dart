import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_controller.dart';
import '../config.dart';
import '../services/backend_api.dart';
import '../widgets/option_picker.dart';

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

  AppController get c => widget.controller;

  void _save() {
    c.settings.backendUrl = _url.text;
    c.settings.athleteId = int.tryParse(_athlete.text.trim());
    c.refreshRecovery();
  }

  Future<void> _test() async {
    _save();
    setState(() => _status = 'Checking…');
    try {
      await BackendApi(c.settings.backendUrl).health();
      setState(() => _status = 'Backend reachable ✓');
    } on BackendException catch (e) {
      setState(() => _status = e.message);
    }
  }

  Future<void> _connectWhoop() async {
    _save();
    final uri = Uri.parse('${c.settings.backendUrl}/auth/whoop/login');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      setState(() => _status = 'Could not open $uri');
    }
  }

  @override
  void dispose() {
    _url.dispose();
    _athlete.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = c.settings;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Backend', style: theme.textTheme.titleMedium),
        TextField(
          controller: _url,
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'Backend base URL',
            helperText: "Your laptop's local IP, e.g. http://192.168.1.23:8000",
          ),
          onSubmitted: (_) => _save(),
        ),
        TextField(
          controller: _athlete,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Athlete ID',
            helperText: 'Shown after connecting WHOOP ("Athlete ID: 1")',
          ),
          onSubmitted: (_) => _save(),
        ),
        const SizedBox(height: 12),
        Row(children: [
          FilledButton(onPressed: _save, child: const Text('Save')),
          const SizedBox(width: 8),
          OutlinedButton(onPressed: _test, child: const Text('Test connection')),
        ]),
        if (_status != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_status!)),
        const Divider(height: 32),
        Text('WHOOP account', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _connectWhoop,
          icon: const Icon(Icons.link),
          label: const Text('Connect WHOOP account'),
        ),
        const SizedBox(height: 4),
        Text(
          "Opens the backend's WHOOP login. WHOOP redirects back to the redirect URL registered on your "
          'WHOOP app. If that is http://localhost:8000/…, finish connecting in a browser on the laptop '
          'running the backend, then type the Athlete ID shown there into the field above.',
          style: theme.textTheme.bodySmall,
        ),
        const Divider(height: 32),
        Text('Defaults for new sessions', style: theme.textTheme.titleMedium),
        OptionDropdown(
          label: 'Sport',
          value: s.sport,
          options: sportOptions,
          onChanged: (v) {
            s.sport = v;
            c.updateSetup(sport: v);
          },
        ),
        OptionDropdown(
          label: 'Session type',
          value: s.sessionType,
          options: sessionTypeOptions,
          onChanged: (v) {
            s.sessionType = v;
            c.updateSetup(sessionType: v);
          },
        ),
        OptionDropdown(
          label: 'Sensor placement',
          value: s.placement,
          options: placementOptions,
          onChanged: (v) {
            s.placement = v;
            c.updateSetup(placement: v);
          },
        ),
        const SizedBox(height: 24),
        Text('Live Training Intelligence $appVersion', style: theme.textTheme.bodySmall),
      ],
    );
  }
}
