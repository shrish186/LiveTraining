import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../app_controller.dart';
import '../coach/live_coach.dart';
import '../config.dart';
import '../sources/whoop_hr_source.dart';
import '../util/day_summary.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

const _weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String _clock(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  final h = d.inHours;
  return '${h > 0 ? '$h:' : ''}${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.controller, required this.onOpenSettings});

  final AppController controller;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final now = DateTime.now();
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            ScreenHeader(
              overline: controller.isRecording ? 'Recording' : 'Today',
              title: '${_weekdays[now.weekday - 1]}, ${_months[now.month - 1]} ${now.day}',
            ),
            _StatusRow(controller: controller, onOpenSettings: onOpenSettings),
            const SizedBox(height: 16),
            if (controller.isRecording) ...[
              _RecordingCard(controller: controller),
              const SizedBox(height: 12),
              if (controller.coach != null) ...[_CoachCard(controller: controller), const SizedBox(height: 12)],
              _HeartRateCard(controller: controller),
              const SizedBox(height: 12),
              _MotionCard(controller: controller),
            ] else ...[
              _RecoveryCard(controller: controller, onOpenSettings: onOpenSettings),
              const SizedBox(height: 12),
              _TodayCard(controller: controller),
              const SizedBox(height: 12),
              _HeartRateCard(controller: controller),
              const SizedBox(height: 12),
              _MotionCard(controller: controller),
              const SizedBox(height: 12),
              _SessionSetupCard(controller: controller),
            ],
          ],
        );
      },
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.controller, required this.onOpenSettings});

  final AppController controller;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final hr = controller.hr;
    final (hrColor, hrText) = switch (hr.state) {
      HrConnection.connected => (AppColors.good, 'Strap connected'),
      HrConnection.scanning || HrConnection.connecting => (AppColors.warning, 'Connecting…'),
      HrConnection.reconnecting => (AppColors.warning, 'Reconnecting…'),
      HrConnection.error => (AppColors.danger, 'Strap issue'),
      HrConnection.idle => (AppColors.textFaint, 'Strap off'),
    };
    final (beColor, beText) = controller.recoveryLoading
        ? (AppColors.warning, 'Syncing…')
        : controller.recovery != null
        ? (AppColors.good, 'Backend synced')
        : (AppColors.textFaint, 'Backend offline');
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        StatusPill(color: hrColor, text: hrText),
        StatusPill(
          color: beColor,
          text: beText,
          onTap: controller.recovery == null && controller.settings.backendUrl.isEmpty
              ? onOpenSettings
              : controller.refreshRecovery,
        ),
      ],
    );
  }
}

class _RecoveryCard extends StatelessWidget {
  const _RecoveryCard({required this.controller, required this.onOpenSettings});

  final AppController controller;
  final VoidCallback onOpenSettings;

  void _showError(BuildContext context, String error) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Recovery unavailable'),
      content: SingleChildScrollView(child: SelectableText(error, style: AppText.dim)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
        TextButton(
          onPressed: () {
            Navigator.pop(context);
            onOpenSettings();
          },
          child: const Text('Settings'),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final r = controller.recovery;
    final score = r?.recoveryScore;
    final color = score == null ? AppColors.textFaint : AppColors.recovery(score);
    final error = controller.recoveryError;

    final Widget details;
    if (score != null) {
      details = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _MiniStat(label: 'Resting HR', value: r!.restingHr?.round().toString() ?? '—', unit: 'bpm'),
          const SizedBox(height: 14),
          _MiniStat(label: 'HRV', value: r.hrvMs?.round().toString() ?? '—', unit: 'ms'),
          if (r.calibrating) ...[
            const SizedBox(height: 10),
            const Text('WHOOP is still calibrating', style: AppText.dim),
          ],
        ],
      );
    } else if (controller.recoveryLoading) {
      details = const Text('Fetching today\'s recovery…', style: AppText.dim);
    } else if (r != null) {
      details = Text('Not scored yet (${r.scoreState ?? 'pending'}).', style: AppText.dim);
    } else {
      details = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(error?.split('\n').first ?? 'No recovery yet.', style: AppText.dim, maxLines: 4),
          const SizedBox(height: 8),
          if (error != null)
            TextButton(
              style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 32)),
              onPressed: () => error.contains('\n') ? _showError(context, error) : onOpenSettings(),
              child: Text(error.contains('\n') ? 'Details' : 'Open Settings'),
            ),
        ],
      );
    }

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel(
            'Recovery',
            trailing: GestureDetector(
              onTap: controller.recoveryLoading ? null : controller.refreshRecovery,
              child: const Icon(Icons.refresh_rounded, size: 18, color: AppColors.textDim),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              RingGauge(
                value: score == null ? 0 : score / 100,
                color: color,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: score?.round().toString() ?? '—', style: AppText.big.copyWith(fontSize: 40)),
                          if (score != null) const TextSpan(text: '%', style: AppText.unit),
                        ],
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(score == null ? 'NO DATA' : 'WHOOP', style: AppText.label.copyWith(fontSize: 9)),
                  ],
                ),
              ),
              const SizedBox(width: 20),
              Expanded(child: details),
            ],
          ),
        ],
      ),
    );
  }
}

/// WHOOP-style day view: WHOOP's day strain in the ring, our training numbers next to it.
class _TodayCard extends StatelessWidget {
  const _TodayCard({required this.controller});

  final AppController controller;

  static const maxStrain = 21.0; // WHOOP's strain scale

  String _minutes(Duration d) => d.inMinutes < 1 && d > Duration.zero ? '<1' : '${d.inMinutes}';

  @override
  Widget build(BuildContext context) {
    final day = controller.today;
    final strain = controller.dayStrain?.strain;
    final (fatigueColor, fatigueText) = switch ((day.sessions, day.fatigue)) {
      (0, _) => (AppColors.textFaint, 'No sessions yet today'),
      (_, FatigueStatus.building) => (
        AppColors.warning,
        'Fatigue building in ${day.fatigueEfforts} effort${day.fatigueEfforts == 1 ? '' : 's'}',
      ),
      _ => (AppColors.good, 'No fatigue signs today'),
    };

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel(
            'Today',
            trailing: Flexible(
              child: Text(
                '${day.sessions} session${day.sessions == 1 ? '' : 's'} · ${_minutes(day.trainingTime)} min',
                style: AppText.dim,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              RingGauge(
                value: strain == null ? 0 : strain / maxStrain,
                color: AppColors.accent,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(strain?.toStringAsFixed(1) ?? '—', style: AppText.big.copyWith(fontSize: 40)),
                    const SizedBox(height: 2),
                    Text(strain == null ? 'NO STRAIN' : 'DAY STRAIN', style: AppText.label.copyWith(fontSize: 9)),
                  ],
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _MiniStat(label: 'Training load', value: day.load.toStringAsFixed(1), unit: ''),
                    const SizedBox(height: 14),
                    _MiniStat(label: 'Efforts', value: '${day.efforts}', unit: ''),
                    if (day.impactLoad != null) ...[
                      const SizedBox(height: 14),
                      _MiniStat(label: 'Impact load', value: day.impactLoad!.round().toString(), unit: 'g'),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: fatigueColor, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(fatigueText, style: AppText.body)),
            ],
          ),
          for (final e in day.entries.reversed.take(4)) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Text(
                  '${e.startedAt.hour.toString().padLeft(2, '0')}:${e.startedAt.minute.toString().padLeft(2, '0')}',
                  style: AppText.dim,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${prettySlug(e.sport)} · ${_minutes(e.duration)} min',
                    style: AppText.dim,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Flexible(
                  child: Text(
                    e.summary == null
                        ? ''
                        : 'load ${e.summary!.load.toStringAsFixed(1)}'
                              '${e.summary!.fatigueEfforts > 0 ? ' · fatigue' : ''}',
                    style: AppText.dim.copyWith(
                      color: (e.summary?.fatigueEfforts ?? 0) > 0 ? AppColors.warning : AppColors.textDim,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value, required this.unit});

  final String label;
  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: AppText.label),
        const SizedBox(height: 4),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(text: value, style: AppText.stat),
              if (unit.isNotEmpty) TextSpan(text: ' $unit', style: AppText.unit),
            ],
          ),
        ),
      ],
    );
  }
}

class _HeartRateCard extends StatelessWidget {
  const _HeartRateCard({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final hr = controller.hr;
    final connected = hr.state == HrConnection.connected;
    final busy =
        hr.state == HrConnection.scanning ||
        hr.state == HrConnection.connecting ||
        hr.state == HrConnection.reconnecting;
    final status = switch (hr.state) {
      HrConnection.idle => 'Turn on Heart Rate Broadcast in the WHOOP app, then connect.',
      HrConnection.scanning => 'Searching for your strap…',
      HrConnection.connecting => 'Connecting to ${hr.deviceName}…',
      HrConnection.connected => hr.deviceName ?? 'Connected',
      HrConnection.reconnecting => 'Signal lost, reconnecting…',
      HrConnection.error => hr.error ?? 'Error',
    };
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel(
            'Heart rate',
            trailing: busy
                ? const SizedBox.square(
                    dimension: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.heart),
                  )
                : Icon(Icons.favorite_rounded, size: 16, color: connected ? AppColors.heart : AppColors.textFaint),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(hr.lastBpm?.toString() ?? '—', style: AppText.hero),
              const SizedBox(width: 6),
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text('BPM', style: AppText.unit),
              ),
              const Spacer(),
              if (controller.isRecording && controller.stats.hrAvg != null)
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      'avg ${controller.stats.hrAvg!.round()}',
                      style: AppText.dim,
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                      softWrap: false,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Sparkline(values: controller.hrHistory.values, color: AppColors.heart, minSpan: 10),
          const SizedBox(height: 12),
          Text(
            status,
            style: hr.state == HrConnection.error ? AppText.dim.copyWith(color: AppColors.danger) : AppText.dim,
          ),
          if (hr.state == HrConnection.error && hr.errorNeedsSettings)
            const TextButton(onPressed: openAppSettings, child: Text('Open Settings')),
          if (!controller.isRecording || !connected) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: connected || busy
                  ? OutlinedButton(onPressed: controller.disconnectHr, child: const Text('Disconnect'))
                  : FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: AppColors.heart, foregroundColor: Colors.white),
                      onPressed: controller.connectHr,
                      icon: const Icon(Icons.bluetooth_rounded),
                      label: const Text('Connect WHOOP HR'),
                    ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MotionCard extends StatelessWidget {
  const _MotionCard({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final error = controller.motionError;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel(
            'Motion',
            trailing: controller.watchLive
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(color: AppColors.good, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Watch · ${prettySlug(controller.watch.placement ?? controller.placement)}',
                        style: AppText.dim,
                      ),
                    ],
                  )
                : Text(prettySlug(controller.placement), style: AppText.dim),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(controller.motionMagnitude.toStringAsFixed(1), style: AppText.big),
              const SizedBox(width: 6),
              const Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: Text('m/s²', style: AppText.unit),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Sparkline(values: controller.motionHistory.values, color: AppColors.accent, height: 44, minSpan: 3),
          if (error != null) ...[
            const SizedBox(height: 10),
            Text(error, style: AppText.dim.copyWith(color: AppColors.danger)),
            if (controller.motionErrorNeedsSettings)
              const TextButton(onPressed: openAppSettings, child: Text('Open Settings')),
          ],
        ],
      ),
    );
  }
}

class _SessionSetupCard extends StatelessWidget {
  const _SessionSetupCard({required this.controller});

  final AppController controller;

  Future<void> _pick(
    BuildContext context,
    String title,
    List<String> options,
    String current,
    void Function(String) onPicked,
  ) async {
    final v = await showOptionSheet(context, title: title, options: options, current: current);
    if (v != null) onPicked(v);
  }

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('New session'),
          const SizedBox(height: 6),
          SettingRow(
            icon: Icons.sports_rounded,
            label: 'Sport',
            value: c.sport,
            onTap: () => _pick(context, 'Sport', sportOptions, c.sport, (v) => c.updateSetup(sport: v)),
          ),
          SettingRow(
            icon: Icons.event_note_rounded,
            label: 'Type',
            value: c.sessionType,
            onTap: () =>
                _pick(context, 'Session type', sessionTypeOptions, c.sessionType, (v) => c.updateSetup(sessionType: v)),
          ),
          SettingRow(
            icon: Icons.accessibility_new_rounded,
            label: 'Sensor on',
            value: c.placement,
            onTap: () =>
                _pick(context, 'Sensor placement', placementOptions, c.placement, (v) => c.updateSetup(placement: v)),
          ),
          const SizedBox(height: 8),
          TextField(
            key: ValueKey('notes-${c.sessions.length}'),
            style: AppText.body,
            decoration: const InputDecoration(labelText: 'Notes (optional)'),
            onChanged: (v) => c.notes = v,
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: FilledButton.icon(
              onPressed: c.startSession,
              icon: const Icon(Icons.play_arrow_rounded, size: 26),
              label: const Text('Start session'),
            ),
          ),
        ],
      ),
    );
  }
}

Color _callColor(CallType t) => switch (t) {
  CallType.readiness => AppColors.accent,
  CallType.warmedUp => AppColors.good,
  CallType.effort => AppColors.load,
  CallType.fatigue => AppColors.warning,
};

/// Live calls: the latest one large, a status line, and the few before it.
class _CoachCard extends StatelessWidget {
  const _CoachCard({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final coach = controller.coach!;
    final calls = controller.calls;
    final latest = calls.isEmpty ? null : calls.last;
    final target = coach.warmupTargetHr;
    final status = !coach.warmedUp
        ? (target == null ? 'Warm-up' : 'Warm-up · HR ${target.round()}+')
        : coach.inEffort
        ? 'In effort'
        : 'Efforts: ${coach.efforts.length}';
    final earlier = calls.reversed.skip(1).take(3).toList();
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel(
            'Coach',
            trailing: Flexible(
              child: Text(status, style: AppText.dim, overflow: TextOverflow.ellipsis),
            ),
          ),
          const SizedBox(height: 12),
          if (latest == null)
            const Text('Calls appear here as you train.', style: AppText.dim)
          else ...[
            Text(latest.title, style: AppText.big.copyWith(fontSize: 24, color: _callColor(latest.type))),
            const SizedBox(height: 4),
            Text(latest.detail, style: AppText.body),
          ],
          for (final call in earlier) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(color: _callColor(call.type), shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(call.title, style: AppText.dim, overflow: TextOverflow.ellipsis),
                ),
                Text(_clock(Duration(milliseconds: call.tMs)), style: AppText.dim),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _RecordingCard extends StatelessWidget {
  const _RecordingCard({required this.controller});

  final AppController controller;

  Future<void> _customEvent(BuildContext context) async {
    final text = TextEditingController();
    final label = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mark event'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final l in ['drill_start', 'drill_end', 'set_start', 'set_end', 'rest'])
                  ActionChip(label: Text(prettySlug(l)), onPressed: () => Navigator.pop(context, l)),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: text,
              decoration: const InputDecoration(labelText: 'Custom label'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, text.text), child: const Text('Mark')),
        ],
      ),
    );
    if (label != null && label.trim().isNotEmpty) controller.markEvent(label.trim().replaceAll(' ', '_'));
  }

  void _mark(BuildContext context, String label) {
    controller.markEvent(label);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('Marked: ${prettySlug(label)}'), duration: const Duration(seconds: 1)));
  }

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final r = c.recorder!;
    final st = c.stats;
    final compact = OutlinedButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      textStyle: Theme.of(context).textTheme.labelLarge!.copyWith(fontSize: 14, fontWeight: FontWeight.w600),
    );
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel(
            '${prettySlug(c.sport)} · ${c.sessionType}',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(color: AppColors.danger, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                Text('REC', style: AppText.label.copyWith(color: AppColors.danger)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Center(child: Text(_clock(r.elapsed), style: AppText.hero.copyWith(fontSize: 72))),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: StatTile(
                  label: 'Avg HR',
                  value: st.hrAvg?.round().toString() ?? '—',
                  unit: 'bpm',
                  color: AppColors.heart,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: StatTile(
                  label: 'Max HR',
                  value: st.hrMax?.round().toString() ?? '—',
                  unit: 'bpm',
                  color: AppColors.heart,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: StatTile(label: 'Load', value: st.load.toStringAsFixed(1), color: AppColors.load),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: StatTile(label: 'Events', value: '${(r.events.length - 1).clamp(0, 9999)}'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: compact,
                  onPressed: () => _mark(context, 'sync_jumps'),
                  icon: const Icon(Icons.height_rounded, size: 18),
                  label: const FittedBox(child: Text('Sync jumps', maxLines: 1)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  style: compact,
                  onPressed: () => _mark(context, 'mark'),
                  icon: const Icon(Icons.flag_rounded, size: 18),
                  label: const FittedBox(child: Text('Mark', maxLines: 1)),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.outlined(
                onPressed: () => _customEvent(context),
                icon: const Icon(Icons.edit_note_rounded),
                tooltip: 'Mark event with a label',
              ),
            ],
          ),
          const SizedBox(height: 12),
          HoldToConfirmButton(label: 'Hold to stop', onConfirmed: c.stopSession),
          const SizedBox(height: 8),
          const Center(child: Text('Keep the app open while recording', style: AppText.dim)),
        ],
      ),
    );
  }
}
