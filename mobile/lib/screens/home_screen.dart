import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../app_controller.dart';
import '../coach/advice.dart';
import '../coach/live_coach.dart';
import '../config.dart';
import '../services/session_store.dart';
import '../sources/sensor_link.dart';
import '../sources/whoop_hr_source.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'open_coach.dart';
import 'sensor_picker.dart';
import 'session_report_screen.dart';

const _weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String _clock(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  final h = d.inHours;
  return '${h > 0 ? '$h:' : ''}${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
}

/// The Live tab. One idea per screen, like the best wearable apps: before a session, how ready you are and
/// how much you've done today, with one Start button; while recording, the clock and the few numbers that
/// matter right now.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.controller, required this.onOpenSettings});

  final AppController controller;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => controller.isRecording
          ? _RecordingView(controller: controller)
          : _TodayView(controller: controller, onOpenSettings: onOpenSettings),
    );
  }
}

// ---- Today (not recording) ------------------------------------------------------------------------------

class _TodayView extends StatelessWidget {
  const _TodayView({required this.controller, required this.onOpenSettings});

  final AppController controller;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final now = DateTime.now();
    final advice = c.homeAdvice;
    final last = c.sessions.where((s) => !c.isRecording && s.player == null).firstOrNull;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${_weekdays[now.weekday - 1]}, ${_months[now.month - 1]} ${now.day}',
                style: AppText.dim.copyWith(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
            _SensorChip(controller: c),
          ],
        ),
        const SizedBox(height: 28),
        _Rings(controller: c),
        const SizedBox(height: 22),
        if (advice.isNotEmpty) _Insight(advice: advice.first, onMore: () => openCoach(context, c)),
        const SizedBox(height: 28),
        if (c.sensor == null) ...[_ConnectSensorRow(controller: c), const SizedBox(height: 14)],
        _SetupChips(controller: c),
        const SizedBox(height: 14),
        SizedBox(
          height: 60,
          child: FilledButton.icon(
            onPressed: c.startSession,
            icon: const Icon(Icons.play_arrow_rounded, size: 28),
            label: const Text('Start session'),
          ),
        ),
        if (last != null) ...[
          const SizedBox(height: 32),
          const Text('LAST SESSION', style: AppText.label),
          const SizedBox(height: 10),
          _LastSessionRow(controller: c, session: last),
        ],
        if (whoopEnabled) ...[const SizedBox(height: 24), _RecoveryCard(controller: c, onOpenSettings: onOpenSettings)],
        const SizedBox(height: 24),
        _HeartRateRow(controller: c),
      ],
    );
  }
}

/// Two rings, WHOOP-style: readiness from the sensor (100 = your usual start) and today's load against
/// your usual day. Each says in words what the number means.
class _Rings extends StatelessWidget {
  const _Rings({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final r = controller.readinessPct;
    final load = controller.todayLoadPct;
    final (rColor, rWord) = r == null
        ? (AppColors.textFaint, 'After 3 sessions')
        : r < 92
        ? (AppColors.warning, 'Below your usual')
        : r > 105
        ? (AppColors.good, 'Sharper than usual')
        : (AppColors.good, 'Normal for you');
    final lWord = load == null
        ? (controller.today.sessions == 0 ? 'No training yet' : 'Usual day after 2 weeks')
        : load >= 130
        ? 'Well above your usual day'
        : load >= 80
        ? 'A full day for you'
        : load > 0
        ? 'Lighter than usual'
        : 'Rest so far';
    return Row(
      children: [
        Expanded(
          child: LabeledRing(
            label: 'READINESS',
            value: r == null ? null : (r / 120).clamp(0.0, 1.0),
            color: rColor,
            number: r == null ? '—' : '${r.round()}',
            unit: r == null ? null : '%',
            word: rWord,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: LabeledRing(
            label: 'LOAD TODAY',
            value: load == null ? (controller.today.load > 0 ? 1.0 : 0.0) : (load / 150).clamp(0.0, 1.0),
            color: AppColors.load,
            number: load == null ? controller.today.load.toStringAsFixed(0) : (load > 300 ? '300+' : '${load.round()}'),
            unit: load == null ? null : '%',
            word: lWord,
          ),
        ),
      ],
    );
  }
}

/// One sentence of advice under the rings; tapping it opens the coach.
class _Insight extends StatelessWidget {
  const _Insight({required this.advice, required this.onMore});

  final Advice advice;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final color = switch (advice.level) {
      AdviceLevel.good => AppColors.good,
      AdviceLevel.info => AppColors.accent,
      AdviceLevel.warn => AppColors.warning,
    };
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onMore,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(advice.title, style: AppText.body.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(advice.detail, style: AppText.dim, maxLines: 2, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.forum_outlined, size: 20, color: AppColors.textDim),
            ],
          ),
        ),
      ),
    );
  }
}

// ---- sensor ---------------------------------------------------------------------------------------------

(Color, String) _sensorStatus(AppController c) {
  final link = c.sensor;
  if (link == null) return (AppColors.textFaint, 'No sensor');
  return switch (link.state) {
    SensorState.live when c.sensorLive => (AppColors.good, link.sensor.name),
    SensorState.lost => (AppColors.danger, 'Out of range'),
    _ => (AppColors.warning, 'Connecting…'),
  };
}

Future<void> _pickSensor(BuildContext context, AppController c) async {
  final picked = await showSensorPicker(context, title: 'Connect a sensor', scan: c.scanSensors);
  if (picked != null) await c.connectSensor(picked);
}

/// Small status chip in the header; tap for the sensor's live signal, or to connect one.
class _SensorChip extends StatelessWidget {
  const _SensorChip({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final (color, text) = _sensorStatus(controller);
    return StatusPill(
      color: color,
      text: text,
      onTap: () => controller.sensor == null
          ? _pickSensor(context, controller)
          : showModalBottomSheet<void>(
              context: context,
              showDragHandle: true,
              builder: (_) => _SensorSheet(controller: controller),
            ),
    );
  }
}

class _ConnectSensorRow extends StatelessWidget {
  const _ConnectSensorRow({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final error = controller.bluetoothError;
    return AppCard(
      onTap: () => _pickSensor(context, controller),
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: AppColors.accent.withValues(alpha: 0.15), shape: BoxShape.circle),
            child: const Icon(Icons.sensors_rounded, color: AppColors.accent, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Connect your sensor', style: AppText.body),
                Text(
                  error ?? 'Strap it above the ankle, arrow to the foot',
                  style: error == null ? AppText.dim : AppText.dim.copyWith(color: AppColors.danger),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (error != null)
            const TextButton(onPressed: openAppSettings, child: Text('Settings'))
          else
            const Icon(Icons.chevron_right_rounded, color: AppColors.textFaint),
        ],
      ),
    );
  }
}

/// The sensor's live signal and controls, in a bottom sheet.
class _SensorSheet extends StatelessWidget {
  const _SensorSheet({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final c = controller;
        final link = c.sensor;
        if (link == null) return const SizedBox(height: 80);
        final (color, status) = _sensorStatus(c);
        final lost = link.decoder.lostPct;
        final peak = c.sensorPeakG;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(link.sensor.name, style: AppText.title.copyWith(fontSize: 22)),
                    const Spacer(),
                    StatusPill(color: color, text: status),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: _Figure(
                        value: peak == null ? '—' : peak.toStringAsFixed(1),
                        unit: 'g',
                        label: 'Peak, 3 s',
                      ),
                    ),
                    Expanded(
                      child: _Figure(value: '${c.sensorRateHz.round()}', unit: 'Hz', label: 'Rate'),
                    ),
                    Expanded(
                      child: _Figure(value: lost.toStringAsFixed(lost < 1 ? 1 : 0), unit: '%', label: 'Lost'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Sparkline(values: c.motionHistory.values, color: AppColors.accent, height: 48, minSpan: 3),
                const SizedBox(height: 12),
                Text(
                  link.state == SensorState.lost
                      ? 'Out of range. Bring the phone closer: it reconnects by itself.'
                      : lost >= 5
                      ? 'Many packets lost: keep the phone within a few metres, on the same side of the body.'
                      : 'Worn on the ${prettySlug(c.placement).toLowerCase()}. The app reconnects to it next time.',
                  style: AppText.dim,
                ),
                if (!c.isRecording) ...[
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            Navigator.pop(context);
                            await _pickSensor(context, c);
                          },
                          child: const Text('Change'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            Navigator.pop(context);
                            c.disconnectSensor();
                          },
                          child: const Text('Forget'),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.value, required this.label, this.unit});

  final String value;
  final String? unit;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(child: Text(value, style: AppText.big.copyWith(fontSize: 30), maxLines: 1)),
            if (unit != null) ...[const SizedBox(width: 3), Text(unit!, style: AppText.unit)],
          ],
        ),
        const SizedBox(height: 2),
        Text(label, style: AppText.dim, maxLines: 1, overflow: TextOverflow.ellipsis),
      ],
    );
  }
}

// ---- session setup, last session, heart rate ------------------------------------------------------------

/// Sport, type and placement as three tappable chips: the defaults are usually right, so they stay small.
class _SetupChips extends StatelessWidget {
  const _SetupChips({required this.controller});

  final AppController controller;

  Future<void> _pick(
    BuildContext context,
    String title,
    List<String> options,
    String current,
    void Function(String) set,
  ) async {
    final v = await showOptionSheet(context, title: title, options: options, current: current);
    if (v != null) set(v);
  }

  @override
  Widget build(BuildContext context) {
    final c = controller;
    Widget chip(IconData icon, String value, VoidCallback onTap) => ActionChip(
      avatar: Icon(icon, size: 16, color: AppColors.textDim),
      label: Text(prettySlug(value)),
      onPressed: onTap,
      backgroundColor: AppColors.surface,
      side: BorderSide.none,
      shape: const StadiumBorder(),
    );
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        chip(
          Icons.sports_rounded,
          c.sport,
          () => _pick(context, 'Sport', sportOptions, c.sport, (v) => c.updateSetup(sport: v)),
        ),
        chip(
          Icons.event_note_rounded,
          c.sessionType,
          () => _pick(context, 'Session type', sessionTypeOptions, c.sessionType, (v) => c.updateSetup(sessionType: v)),
        ),
        chip(
          Icons.accessibility_new_rounded,
          c.placement,
          () => _pick(context, 'Sensor on', placementOptions, c.placement, (v) => c.updateSetup(placement: v)),
        ),
      ],
    );
  }
}

class _LastSessionRow extends StatelessWidget {
  const _LastSessionRow({required this.controller, required this.session});

  final AppController controller;
  final LocalSession session;

  @override
  Widget build(BuildContext context) {
    final s = session;
    final sum = s.summary;
    final t = s.startedAt;
    final when = t == null
        ? ''
        : '${_weekdays[t.weekday - 1].substring(0, 3)} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    final first = sum?.firstActionG, lastG = sum?.lastActionG;
    final facts = [
      '${s.duration.inMinutes} min',
      if (sum?.actions != null) '${sum!.actions} ${sum.actionsLabel ?? 'actions'}',
      if (first != null && lastG != null && first > 0)
        'landing ${lastG >= first ? '+' : '−'}${((lastG / first - 1) * 100).abs().round()}%',
      if (sum != null && sum.actions == null) 'load ${sum.load.toStringAsFixed(0)}',
    ].join(' · ');
    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SessionReportScreen(session: s, controller: controller),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${prettySlug(s.sport)} · $when', style: AppText.body),
                const SizedBox(height: 2),
                Text(facts, style: AppText.dim, maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: AppColors.textFaint),
        ],
      ),
    );
  }
}

/// Heart rate is optional: a quiet one-line row, not a card.
class _HeartRateRow extends StatelessWidget {
  const _HeartRateRow({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final hr = controller.hr;
    final connected = hr.state == HrConnection.connected;
    final idle = hr.state == HrConnection.idle;
    final text = switch (hr.state) {
      HrConnection.idle => 'Heart-rate strap (optional)',
      HrConnection.connected => '${hr.lastBpm ?? '—'} bpm · ${hr.deviceName ?? 'strap'}',
      HrConnection.error => hr.error ?? 'Heart-rate strap issue',
      _ => 'Heart rate: connecting…',
    };
    return Row(
      children: [
        Icon(Icons.favorite_rounded, size: 16, color: connected ? AppColors.heart : AppColors.textFaint),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: AppText.dim, maxLines: 2, overflow: TextOverflow.ellipsis),
        ),
        TextButton(
          onPressed: idle || hr.state == HrConnection.error ? controller.connectHr : controller.disconnectHr,
          child: Text(idle || hr.state == HrConnection.error ? 'Connect' : 'Disconnect'),
        ),
      ],
    );
  }
}

// ---- recording ------------------------------------------------------------------------------------------

/// While recording: the clock, one hero number, three small ones, the latest call, mark and stop.
class _RecordingView extends StatelessWidget {
  const _RecordingView({required this.controller});

  final AppController controller;

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
    final coach = c.coach;
    final actions = coach?.actions;
    final strikes = coach?.strikes;
    final hasHr = c.stats.hrAvg != null || c.hr.state == HrConnection.connected;
    final (heroValue, heroLabel) = actions != null
        ? ('${actions.actions.length}', actions.cfg.labelPlural.toUpperCase())
        : (c.stats.load.toStringAsFixed(1), 'LOAD');
    final small = <(String, String, String?)>[
      if (strikes != null) ('Hardest hit', strikes.hardestG?.toStringAsFixed(1) ?? '—', 'g'),
      if (strikes != null) ('Footstrikes', '${strikes.strikes}', null),
      if (actions != null)
        ('Load', c.stats.load.toStringAsFixed(1), null)
      else
        ('Efforts', '${coach?.efforts.length ?? 0}', null),
      if (hasHr) ('Heart rate', c.hr.lastBpm?.toString() ?? '—', 'bpm'),
    ].take(3).toList();
    final (sColor, sText) = _sensorStatus(c);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(color: AppColors.danger, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${prettySlug(c.sport)} · ${c.sessionType}'.toUpperCase(),
                style: AppText.label.copyWith(color: AppColors.danger),
              ),
            ),
            StatusPill(color: sColor, text: sText),
          ],
        ),
        const SizedBox(height: 24),
        Center(child: Text(_clock(r.elapsed), style: AppText.hero.copyWith(fontSize: 76, letterSpacing: -3))),
        const SizedBox(height: 28),
        Center(
          child: Text(heroValue, style: AppText.hero.copyWith(fontSize: 96, color: AppColors.accent)),
        ),
        Center(child: Text(heroLabel, style: AppText.label)),
        const SizedBox(height: 28),
        Row(
          children: [
            for (final (label, value, unit) in small)
              Expanded(
                child: _Figure(value: value, unit: unit, label: label),
              ),
          ],
        ),
        const SizedBox(height: 24),
        if (coach != null) _CoachCard(controller: c),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _mark(context, 'mark'),
                icon: const Icon(Icons.flag_rounded, size: 18),
                label: const Text('Mark'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _mark(context, 'sync_jumps'),
                icon: const Icon(Icons.height_rounded, size: 18),
                label: const FittedBox(child: Text('Sync jumps', maxLines: 1)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        HoldToConfirmButton(label: 'Hold to stop', onConfirmed: c.stopSession),
        const SizedBox(height: 8),
        const Center(child: Text('Keep the app open while recording', style: AppText.dim)),
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

Color _callColor(CallType t) => switch (t) {
  CallType.readiness => AppColors.accent,
  CallType.warmedUp => AppColors.good,
  CallType.effort => AppColors.load,
  CallType.action => AppColors.load,
  CallType.fatigue => AppColors.warning,
};

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
        : coach.actions != null
        ? '${coach.actions!.cfg.labelPlural[0].toUpperCase()}${coach.actions!.cfg.labelPlural.substring(1)}: '
              '${coach.actions!.actions.length}'
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
