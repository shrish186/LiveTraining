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
import 'trends_screen.dart';

String _capital(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

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
    final advice = c.homeAdvice;
    final last = c.sessions.where((s) => s.player == null).firstOrNull;
    final today = c.today;
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment(0, 0.2),
          colors: [AppColors.backgroundTop, AppColors.background],
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        children: [
          _Header(controller: c),
          const SizedBox(height: 14),
          _StatusLine(controller: c),
          const SizedBox(height: 16),
          _ReadinessCard(controller: c),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _LastSessionTile(controller: c, session: last),
              ),
              const SizedBox(width: 12),
              Expanded(child: _SensorTile(controller: c)),
            ],
          ),
          const SizedBox(height: 30),
          Text('My day', style: AppText.title.copyWith(fontSize: 24)),
          const SizedBox(height: 14),
          if (advice.isNotEmpty) ...[
            _Outlook(advice: advice.first, onTap: () => openCoach(context, c)),
            const SizedBox(height: 12),
          ],
          _TodaySessions(
            controller: c,
            sessions: c.sessions.where((s) => s.player == null && _isToday(s.startedAt)).toList(),
          ),
          const SizedBox(height: 12),
          _WeekChecks(controller: c),
          if (whoopEnabled) ...[
            const SizedBox(height: 12),
            _RecoveryCard(controller: c, onOpenSettings: onOpenSettings),
          ],
          const SizedBox(height: 16),
          _HeartRateRow(controller: c),
          if (today.sessions == 0 && c.sessions.isEmpty) ...[
            const SizedBox(height: 8),
            const Text('Tap + to record your first session.', style: AppText.dim, textAlign: TextAlign.center),
          ],
        ],
      ),
    );
  }
}

bool _isToday(DateTime? t) {
  if (t == null) return false;
  final n = DateTime.now();
  return t.year == n.year && t.month == n.month && t.day == n.day;
}

/// "Today", the date, the training streak and the coach.
class _Header extends StatelessWidget {
  const _Header({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June', //
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    final now = DateTime.now();
    final streak = controller.streakDays;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Today', style: AppText.title.copyWith(fontSize: 32)),
              Text('${days[now.weekday - 1]} ${now.day} ${months[now.month - 1]}', style: AppText.dim),
            ],
          ),
        ),
        Tooltip(
          message: '$streak day${streak == 1 ? '' : 's'} in a row',
          child: Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: streak > 0 ? AppColors.brand.withValues(alpha: 0.14) : AppColors.surface,
              borderRadius: BorderRadius.circular(19),
            ),
            child: Row(
              children: [
                Icon(Icons.bolt_rounded, size: 20, color: streak > 0 ? AppColors.brand : AppColors.textFaint),
                const SizedBox(width: 4),
                Text('$streak', style: AppText.body.copyWith(fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
        const SizedBox(width: 4),
        IconButton(
          tooltip: 'Ask the coach',
          onPressed: () => openCoach(context, controller),
          icon: const Icon(Icons.auto_awesome_rounded, color: AppColors.textDim),
        ),
      ],
    );
  }
}

/// One slim line: is the sensor streaming? Tap to connect, or to see its signal.
class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final link = c.sensor;
    final blocked = link == null && c.bluetoothError != null;
    final (Color color, String text, String? action) = blocked
        ? (AppColors.danger, 'Bluetooth not allowed', 'Settings')
        : link == null
        ? (AppColors.textFaint, 'No sensor connected', 'Connect')
        : link.state == SensorState.live && c.sensorLive
        ? (AppColors.good, 'Sensor streaming · ${c.sensorRateHz.round()} Hz', null)
        : link.state == SensorState.lost
        ? (AppColors.danger, 'Sensor out of range · reconnecting', null)
        : (AppColors.warning, 'Connecting to ${link.sensor.name}…', null);
    return Material(
      color: AppColors.surface,
      shape: StadiumBorder(side: BorderSide(color: color.withValues(alpha: 0.5))),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: blocked
            ? openAppSettings
            : link == null
            ? () => _pickSensor(context, c)
            : () => showModalBottomSheet<void>(
                context: context,
                showDragHandle: true,
                builder: (_) => _SensorSheet(controller: c),
              ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  text,
                  style: AppText.body.copyWith(fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (action != null)
                Text(
                  action,
                  style: AppText.body.copyWith(fontSize: 14, color: AppColors.brand, fontWeight: FontWeight.w700),
                )
              else
                const Icon(Icons.chevron_right_rounded, size: 20, color: AppColors.textFaint),
            ],
          ),
        ),
      ),
    );
  }
}

/// The hero: readiness on a half arc (the tick marks your usual start), then today's load and the week as
/// meters against your usual.
class _ReadinessCard extends StatelessWidget {
  const _ReadinessCard({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final r = c.readinessPct;
    final load = c.todayLoadPct;
    final week = c.weekLoadPct;
    final word = r == null
        ? 'Measured from your first over, after 3 sessions'
        : r < 92
        ? 'Softer start than usual: ease in'
        : r > 105
        ? 'Sharper than usual: a good day to push'
        : 'Normal for you';
    String pct(double v) => v > 300 ? '300+%' : '${v.round()}%';
    return AppCard(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => TrendsScreen(trends: c.trends, onAskCoach: () => openCoach(context, c)),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 14),
      child: Column(
        children: [
          ArcGauge(
            value: r == null ? 0 : r / 120,
            marker: 100 / 120,
            colors: r != null && r < 92
                ? const [AppColors.warning, AppColors.warning]
                : const [Color(0xFF6FE3B4), AppColors.brand],
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(r == null ? '—' : '${r.round()}', style: AppText.hero.copyWith(fontSize: 58)),
                    if (r != null) Text('%', style: AppText.stat.copyWith(color: AppColors.textDim)),
                  ],
                ),
                Text('Readiness', style: AppText.body.copyWith(fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          Text(word, style: AppText.dim, textAlign: TextAlign.center),
          const SizedBox(height: 14),
          const Divider(height: 1, color: AppColors.outline),
          const SizedBox(height: 10),
          Meter(
            label: 'Load today',
            valueText: load == null ? c.today.load.toStringAsFixed(0) : pct(load),
            value: load == null ? (c.today.load > 0 ? 1 : 0) : load / 150,
            marker: load == null ? null : 100 / 150,
            color: AppColors.load,
            caption: load == null ? 'usual day after 2 weeks' : 'of your usual day',
          ),
          const SizedBox(height: 4),
          Meter(
            label: 'This week',
            valueText: week == null ? '—' : pct(week),
            value: week == null ? 0 : week / 150,
            marker: week == null ? null : 100 / 150,
            color: week != null && week > 130 ? AppColors.warning : AppColors.accent,
            caption: week == null ? 'after 3 weeks' : 'of your usual week',
          ),
        ],
      ),
    );
  }
}

/// A small card with a title, an icon square and two lines (like a wearable's monitor tiles).
class _Tile extends StatelessWidget {
  const _Tile({
    required this.title,
    required this.badge,
    required this.badgeColor,
    required this.line1,
    required this.line2,
    this.onTap,
  });

  final String title;
  final Widget badge;
  final Color badgeColor;
  final String line1;
  final String line2;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: AppText.section.copyWith(fontSize: 15),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Icon(Icons.chevron_right_rounded, size: 20, color: AppColors.textDim),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: badge,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      line1,
                      style: AppText.body.copyWith(fontSize: 14, color: badgeColor, fontWeight: FontWeight.w700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(line2, style: AppText.dim, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LastSessionTile extends StatelessWidget {
  const _LastSessionTile({required this.controller, required this.session});

  final AppController controller;
  final LocalSession? session;

  @override
  Widget build(BuildContext context) {
    final s = session;
    final sum = s?.summary;
    final first = sum?.firstActionG, lastG = sum?.lastActionG;
    final held = first != null && lastG != null && first > 0 ? lastG / first * 100 : null;
    final color = held == null ? AppColors.accent : (held < 90 ? AppColors.warning : AppColors.good);
    final big = sum?.actions != null ? '${sum!.actions}' : (sum == null ? '—' : sum.load.toStringAsFixed(0));
    return _Tile(
      title: 'Last session',
      badge: Text(
        big,
        style: AppText.body.copyWith(fontWeight: FontWeight.w800, color: color),
      ),
      badgeColor: color,
      line1: s == null
          ? 'None yet'
          : held == null
          ? (sum?.actions != null ? _capital(sum!.actionsLabel ?? 'actions') : 'Load')
          : (held < 90 ? 'Faded ${(100 - held).round()}%' : 'Held up'),
      line2: s == null ? 'Tap + to start' : '${s.duration.inMinutes} min',
      onTap: s == null
          ? null
          : () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => SessionReportScreen(session: s, controller: controller),
              ),
            ),
    );
  }
}

class _SensorTile extends StatelessWidget {
  const _SensorTile({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final link = c.sensor;
    final (color, _) = _sensorStatus(c);
    final peak = c.sensorPeakG;
    final lost = link?.decoder.lostPct ?? 0;
    return _Tile(
      title: 'Sensor',
      badge: Icon(
        link == null ? Icons.sensors_off_rounded : Icons.sensors_rounded,
        color: color == AppColors.textFaint ? AppColors.accent : color,
        size: 22,
      ),
      badgeColor: color == AppColors.textFaint ? AppColors.accent : color,
      line1: link == null
          ? 'Connect'
          : c.sensorLive
          ? (lost >= 5 ? 'Weak signal' : 'Good signal')
          : (link.state == SensorState.lost ? 'Out of range' : 'Connecting'),
      line2: link == null ? 'Tap to pair' : (peak == null ? link.sensor.name : 'Peak ${peak.toStringAsFixed(1)} g'),
      onTap: () => link == null
          ? _pickSensor(context, c)
          : showModalBottomSheet<void>(
              context: context,
              showDragHandle: true,
              builder: (_) => _SensorSheet(controller: c),
            ),
    );
  }
}

/// The coach's one-line outlook for today, as a banner.
class _Outlook extends StatelessWidget {
  const _Outlook({required this.advice, required this.onTap});

  final Advice advice;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = switch (advice.level) {
      AdviceLevel.good => AppColors.good,
      AdviceLevel.info => AppColors.accent,
      AdviceLevel.warn => AppColors.warning,
    };
    return Material(
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: BoxDecoration(gradient: LinearGradient(colors: [color.withValues(alpha: 0.32), AppColors.surface])),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 12, 16),
            child: Row(
              children: [
                const Icon(Icons.auto_awesome_rounded, color: AppColors.text, size: 24),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Coach's outlook", style: AppText.body.copyWith(fontSize: 17, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(advice.title, style: AppText.dim, maxLines: 2, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: AppColors.text),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Today's sessions as rows with a coloured block (like a wearable's activity list), and Start.
class _TodaySessions extends StatelessWidget {
  const _TodaySessions({required this.controller, required this.sessions});

  final AppController controller;
  final List<LocalSession> sessions;

  @override
  Widget build(BuildContext context) {
    String hm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    return AppCard(
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 4),
            child: Text("Today's sessions", style: AppText.section),
          ),
          const SizedBox(height: 14),
          for (final s in sessions) ...[
            Material(
              color: AppColors.surfaceHigh,
              borderRadius: BorderRadius.circular(14),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SessionReportScreen(session: s, controller: controller),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    children: [
                      Container(
                        width: 96,
                        height: 48,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.load.withValues(alpha: 0.75),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          s.summary?.actions != null
                              ? '${s.summary!.actions}'
                              : (s.summary?.load.toStringAsFixed(1) ?? '—'),
                          style: AppText.stat,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          prettySlug(s.sport),
                          style: AppText.section,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(s.startedAt == null ? '' : hm(s.startedAt!), style: AppText.dim),
                          Text('${s.duration.inMinutes} min', style: AppText.dim),
                        ],
                      ),
                      const SizedBox(width: 6),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              style: FilledButton.styleFrom(backgroundColor: AppColors.surfaceHigh, foregroundColor: AppColors.text),
              onPressed: () => showStartSheet(context, controller),
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Start session'),
            ),
          ),
        ],
      ),
    );
  }
}

/// This week as seven days with a tick for each day trained.
class _WeekChecks extends StatelessWidget {
  const _WeekChecks({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final days = controller.trends.days;
    final week = days.sublist(days.length - 7);
    const names = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
    return AppCard(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => TrendsScreen(trends: controller.trends, onAskCoach: () => openCoach(context, controller)),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(18, 18, 14, 18),
      child: Column(
        children: [
          const Row(
            children: [
              Expanded(child: Text('This week', style: AppText.section)),
              Icon(Icons.chevron_right_rounded, color: AppColors.textDim),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              for (var i = 0; i < 7; i++)
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        names[week[i].day.weekday - 1],
                        style: AppText.label.copyWith(color: i == 6 ? AppColors.text : AppColors.textDim),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          color: week[i].sessions > 0 ? AppColors.brand : AppColors.surfaceHigh,
                          border: week[i].sessions > 0 ? null : Border.all(color: AppColors.outline, width: 1.5),
                        ),
                        child: week[i].sessions > 0
                            ? const Icon(Icons.bolt_rounded, size: 20, color: AppColors.onBrand)
                            : null,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Sport, type and placement, then Start: opened from + so the screen stays short.
void showStartSheet(BuildContext context, AppController c) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheet) => ListenableBuilder(
      listenable: c,
      builder: (sheet, _) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('New session', style: AppText.title),
              const SizedBox(height: 16),
              _SetupChips(controller: c),
              if (c.sensor == null) ...[
                const SizedBox(height: 12),
                const Text(
                  'No sensor connected: the phone\'s motion is recorded instead.',
                  style: AppText.dim,
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 18),
              SizedBox(
                height: 58,
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(sheet);
                    c.startSession();
                  },
                  icon: const Icon(Icons.play_arrow_rounded, size: 28),
                  label: const Text('Start session'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
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
        : (c.stats.load.toStringAsFixed(1), 'Load');
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
