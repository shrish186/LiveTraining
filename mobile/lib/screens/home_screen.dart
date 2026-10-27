import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../config.dart';
import '../sources/whoop_hr_source.dart';
import '../widgets/option_picker.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _HeartRateCard(controller: controller),
          const SizedBox(height: 12),
          _MotionCard(controller: controller),
          const SizedBox(height: 12),
          _RecoveryCard(controller: controller),
          const SizedBox(height: 12),
          _SessionCard(controller: controller),
        ],
      ),
    );
  }
}

class _HeartRateCard extends StatelessWidget {
  const _HeartRateCard({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final hr = controller.hr;
    final theme = Theme.of(context);
    final (label, busy) = switch (hr.state) {
      HrConnection.idle => ('Not connected', false),
      HrConnection.scanning => ('Searching for heart-rate broadcast…', true),
      HrConnection.connecting => ('Connecting to ${hr.deviceName}…', true),
      HrConnection.connected => ('Connected: ${hr.deviceName}', false),
      HrConnection.reconnecting => ('Signal lost, reconnecting…', true),
      HrConnection.error => (hr.error ?? 'Error', false),
    };
    final connected = hr.state != HrConnection.idle && hr.state != HrConnection.error;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.favorite, color: theme.colorScheme.error),
              const SizedBox(width: 8),
              Text('WHOOP heart rate', style: theme.textTheme.titleMedium),
              const Spacer(),
              if (busy) const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            ]),
            const SizedBox(height: 8),
            Center(
              child: Text.rich(TextSpan(children: [
                TextSpan(
                  text: hr.lastBpm?.toString() ?? '--',
                  style: theme.textTheme.displayLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                TextSpan(text: ' bpm', style: theme.textTheme.titleLarge),
              ])),
            ),
            Text(label, style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: connected
                  ? OutlinedButton(onPressed: controller.disconnectHr, child: const Text('Disconnect'))
                  : FilledButton.icon(
                      onPressed: controller.connectHr,
                      icon: const Icon(Icons.bluetooth),
                      label: const Text('Connect WHOOP HR'),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MotionCard extends StatelessWidget {
  const _MotionCard({required this.controller});

  final AppController controller;
  static const _scaleMax = 15.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final m = controller.motionMagnitude;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.directions_run),
            const SizedBox(width: 8),
            Text('Motion', style: theme.textTheme.titleMedium),
            const Spacer(),
            Text('${m.toStringAsFixed(1)} m/s²', style: theme.textTheme.titleLarge),
          ]),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: (m / _scaleMax).clamp(0, 1), minHeight: 10),
          if (controller.motionError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(controller.motionError!, style: TextStyle(color: theme.colorScheme.error)),
            ),
        ]),
      ),
    );
  }
}

class _RecoveryCard extends StatelessWidget {
  const _RecoveryCard({required this.controller});

  final AppController controller;

  // WHOOP's own recovery bands.
  Color _color(double score) => score >= 67
      ? const Color(0xFF16A34A)
      : score >= 34
          ? const Color(0xFFEAB308)
          : const Color(0xFFDC2626);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = controller.recovery;
    final score = r?.recoveryScore;
    Widget body;
    if (controller.recoveryLoading && r == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (r == null) {
      body = Text(controller.recoveryError ?? 'No recovery yet.', style: theme.textTheme.bodyMedium);
    } else if (score == null) {
      body = Text('Recovery not scored yet (${r.scoreState ?? 'pending'}).');
    } else {
      body = Row(children: [
        Text('${score.round()}%',
            style: theme.textTheme.displaySmall?.copyWith(color: _color(score), fontWeight: FontWeight.bold)),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (r.restingHr != null) Text('Resting HR ${r.restingHr!.round()} bpm'),
            if (r.hrvMs != null) Text('HRV ${r.hrvMs!.toStringAsFixed(0)} ms'),
            if (r.calibrating) Text('WHOOP is still calibrating', style: theme.textTheme.bodySmall),
          ]),
        ),
      ]);
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.battery_charging_full),
            const SizedBox(width: 8),
            Text("Today's recovery", style: theme.textTheme.titleMedium),
            const Spacer(),
            IconButton(
              onPressed: controller.recoveryLoading ? null : controller.refreshRecovery,
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh',
            ),
          ]),
          body,
        ]),
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({required this.controller});

  final AppController controller;

  String _clock(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final h = d.inHours;
    return '${h > 0 ? '$h:' : ''}${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
  }

  Future<void> _customEvent(BuildContext context) async {
    final text = TextEditingController();
    final label = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mark event'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Wrap(spacing: 8, children: [
            for (final l in ['drill_start', 'drill_end', 'set_start', 'set_end', 'rest'])
              ActionChip(label: Text(l), onPressed: () => Navigator.pop(context, l)),
          ]),
          TextField(controller: text, decoration: const InputDecoration(labelText: 'Custom label')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, text.text), child: const Text('Mark')),
        ],
      ),
    );
    if (label != null && label.trim().isNotEmpty) controller.markEvent(label.trim().replaceAll(' ', '_'));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = controller;
    final r = c.recorder;
    final recording = c.isRecording;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Session', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OptionChip(
              icon: Icons.sports,
              label: 'Sport',
              value: c.sport,
              options: sportOptions,
              enabled: !recording,
              onChanged: (v) => c.updateSetup(sport: v),
            ),
            OptionChip(
              icon: Icons.event_note,
              label: 'Type',
              value: c.sessionType,
              options: sessionTypeOptions,
              enabled: !recording,
              onChanged: (v) => c.updateSetup(sessionType: v),
            ),
            OptionChip(
              icon: Icons.accessibility_new,
              label: 'Sensor on',
              value: c.placement,
              options: placementOptions,
              enabled: !recording,
              onChanged: (v) => c.updateSetup(placement: v),
            ),
          ]),
          if (!recording)
            TextField(
              key: ValueKey('notes-${r?.sessionId}'),
              decoration: const InputDecoration(labelText: 'Notes (optional)'),
              onChanged: (v) => c.notes = v,
            ),
          const SizedBox(height: 16),
          if (recording && r != null) ...[
            Center(child: Text(_clock(r.elapsed), style: theme.textTheme.displayMedium)),
            Center(
              child: Text(
                'acc ${r.count('phone', 'acc')} · gyro ${r.count('phone', 'gyro')} · '
                'hr ${r.count('whoop_hr', 'hr')} · rr ${r.count('whoop_hr', 'rr')} · events ${r.events.length}',
                style: theme.textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => c.markEvent('sync_jumps'),
                  icon: const Icon(Icons.height),
                  label: const Text('Mark sync jumps'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => c.markEvent('mark'),
                  icon: const Icon(Icons.flag),
                  label: const Text('Mark event'),
                ),
              ),
              IconButton(
                onPressed: () => _customEvent(context),
                icon: const Icon(Icons.edit_note),
                tooltip: 'Mark event with a label',
              ),
            ]),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.error),
                // Long press, so a pocket or armband touch can't end the session.
                onPressed: () => ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(const SnackBar(content: Text('Hold to stop the session'))),
                onLongPress: c.stopSession,
                icon: const Icon(Icons.stop),
                label: const Text('Hold to stop'),
              ),
            ),
          ] else
            SizedBox(
              width: double.infinity,
              height: 56,
              child: FilledButton.icon(
                onPressed: c.startSession,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Start session'),
              ),
            ),
        ]),
      ),
    );
  }
}
