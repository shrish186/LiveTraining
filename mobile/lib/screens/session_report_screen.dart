import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../coach/live_coach.dart';
import '../report/session_report.dart';
import '../report/signal_quality.dart';
import '../services/session_store.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String _mmss(double seconds) {
  final s = seconds.round();
  return '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
}

/// One recorded session, analysed on the phone: timeline, efforts, heart rate, impact, data quality.
class SessionReportScreen extends StatefulWidget {
  const SessionReportScreen({super.key, required this.session});

  final LocalSession session;

  @override
  State<SessionReportScreen> createState() => _SessionReportScreenState();
}

class _SessionReportScreenState extends State<SessionReportScreen> {
  late final Future<SessionReport> _report = _load();

  Future<SessionReport> _load() async {
    final yaml = await rootBundle.loadString('assets/sport_profiles.yaml');
    final csv = widget.session.csv.path, meta = widget.session.metadataFile.path;
    // Parsing and replaying a long session takes a moment: keep it off the UI thread.
    return Isolate.run(() => SessionReport.fromFiles(csv, meta, yaml));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: AppColors.background, surfaceTintColor: Colors.transparent),
      body: FutureBuilder<SessionReport>(
        future: _report,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Could not read this session.\n${snapshot.error}', style: AppText.dim),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator(color: AppColors.accent));
          }
          return SessionReportView(session: widget.session, report: snapshot.data!);
        },
      ),
    );
  }
}

class SessionReportView extends StatelessWidget {
  const SessionReportView({super.key, required this.session, required this.report});

  final LocalSession session;
  final SessionReport report;

  @override
  Widget build(BuildContext context) {
    final r = report;
    final start = session.startedAt;
    final overline = start == null
        ? 'Session'
        : '${_weekdays[start.weekday - 1]} ${start.day} ${_months[start.month - 1]} · '
              '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}';
    final sensor = switch (r.motionSource) {
      null => 'No motion',
      'phone' => 'Phone',
      final s => prettySlug(s),
    };
    final placement = r.placement == null ? null : prettySlug(r.placement!);
    // "Phone armband" already says it is the phone; a body sensor reads "Apple watch on ankle".
    final where = placement == null
        ? sensor
        : r.motionSource == 'phone'
        ? placement
        : '$sensor on ${placement.toLowerCase()}';
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      children: [
        ScreenHeader(overline: overline, title: '${prettySlug(session.sport)} · ${session.sessionType}'),
        Text('${_mmss(r.durationS)} · $where', style: AppText.dim),
        const SizedBox(height: 16),
        _Tiles(report: r),
        const SizedBox(height: 12),
        _TimelineCard(report: r),
        const SizedBox(height: 12),
        _EffortsCard(report: r),
        const SizedBox(height: 12),
        _QualityCard(report: r),
      ],
    );
  }
}

class _Tiles extends StatelessWidget {
  const _Tiles({required this.report});

  final SessionReport report;

  @override
  Widget build(BuildContext context) {
    final r = report;
    final tiles = [
      StatTile(label: 'Efforts', value: '${r.efforts.length}', color: AppColors.accent),
      StatTile(label: 'Load', value: r.load.toStringAsFixed(1), color: AppColors.load),
      StatTile(label: 'Avg HR', value: r.hrAvg?.round().toString() ?? '—', unit: 'bpm', color: AppColors.heart),
      StatTile(label: 'Max HR', value: r.hrMax?.round().toString() ?? '—', unit: 'bpm', color: AppColors.heart),
      if (r.impactLoad != null) StatTile(label: 'Impact load', value: r.impactLoad!.round().toString(), unit: 'g'),
      if (r.strikes != null) StatTile(label: 'Footstrikes', value: '${r.strikes}'),
      if (r.actions != null)
        StatTile(
          label: r.actionsLabel![0].toUpperCase() + r.actionsLabel!.substring(1),
          value: '${r.actions!.length}',
          color: AppColors.accent,
        ),
      if (r.actionDriftPct != null)
        StatTile(
          label: 'Landing, last vs first',
          value: '${r.actionDriftPct! >= 0 ? '+' : ''}${r.actionDriftPct!.round()}',
          unit: '%',
          color: r.actionDriftPct! <= -10 ? AppColors.warning : null,
        ),
    ];
    return Column(
      children: [
        for (var i = 0; i < tiles.length; i += 2) ...[
          if (i > 0) const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: tiles[i]),
              const SizedBox(width: 10),
              Expanded(child: i + 1 < tiles.length ? tiles[i + 1] : const SizedBox()),
            ],
          ),
        ],
      ],
    );
  }
}

class _TimelineCard extends StatelessWidget {
  const _TimelineCard({required this.report});

  final SessionReport report;

  Widget _legend(Color color, String text) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 6),
      Text(text, style: AppText.dim),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final r = report;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('Timeline'),
          const SizedBox(height: 14),
          SizedBox(
            height: 170,
            width: double.infinity,
            child: CustomPaint(painter: _TimelinePainter(r)),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('00:00', style: AppText.dim),
              Text(_mmss(r.durationS / 2), style: AppText.dim),
              Text(_mmss(r.durationS), style: AppText.dim),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 6,
            children: [
              _legend(AppColors.accent, 'Motion'),
              if (r.hrMax != null) _legend(AppColors.heart, 'Heart rate'),
              _legend(AppColors.load, 'Effort'),
              if (r.fatigueEfforts > 0) _legend(AppColors.warning, 'Fatigue building'),
              if (r.events.isNotEmpty) _legend(AppColors.textDim, 'Your marks'),
            ],
          ),
        ],
      ),
    );
  }
}

class _TimelinePainter extends CustomPainter {
  _TimelinePainter(this.r);

  final SessionReport r;

  @override
  void paint(Canvas canvas, Size size) {
    if (r.durationS <= 0) return;
    double xAt(double tS) => tS / r.durationS * size.width;

    // Effort bands behind everything.
    for (final e in r.efforts) {
      final color = e.fatigue ? AppColors.warning : AppColors.load;
      final rect = Rect.fromLTRB(xAt(e.startS), 0, math.max(xAt(e.endS), xAt(e.startS) + 2), size.height);
      canvas.drawRect(rect, Paint()..color = color.withValues(alpha: 0.22));
    }

    // Motion: filled area, scaled to its own maximum (at least a little above the effort threshold).
    final top = math.max(r.motion.whereType<double>().fold(0.0, math.max), r.effortThreshold * 1.2);
    double yMotion(double v) => size.height - v / top * (size.height - 4);
    final n = r.motion.length;
    final dx = n > 1 ? size.width / (n - 1) : size.width;
    final line = Path(), fill = Path()..moveTo(0, size.height);
    var started = false;
    for (var i = 0; i < n; i++) {
      final v = r.motion[i] ?? 0;
      final p = Offset(i * dx, yMotion(v));
      started ? line.lineTo(p.dx, p.dy) : line.moveTo(p.dx, p.dy);
      fill.lineTo(p.dx, p.dy);
      started = true;
    }
    fill
      ..lineTo((n - 1) * dx, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.accent.withValues(alpha: 0.30), AppColors.accent.withValues(alpha: 0)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = AppColors.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeJoin = StrokeJoin.round,
    );

    // Effort threshold: thin dashed line.
    final ty = yMotion(r.effortThreshold);
    final dash = Paint()
      ..color = AppColors.textFaint
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += 8) {
      canvas.drawLine(Offset(x, ty), Offset(math.min(x + 4, size.width), ty), dash);
    }

    // Heart rate on its own scale.
    final hrValues = r.hr.whereType<double>();
    if (hrValues.isNotEmpty) {
      var lo = hrValues.reduce(math.min), hi = hrValues.reduce(math.max);
      if (hi - lo < 20) {
        final mid = (hi + lo) / 2;
        lo = mid - 10;
        hi = mid + 10;
      }
      final path = Path();
      var drawing = false;
      for (var i = 0; i < r.hr.length; i++) {
        final v = r.hr[i];
        if (v == null) {
          drawing = false;
          continue;
        }
        final p = Offset(i * dx, size.height - 6 - (v - lo) / (hi - lo) * (size.height - 16));
        drawing ? path.lineTo(p.dx, p.dy) : path.moveTo(p.dx, p.dy);
        drawing = true;
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = AppColors.heart
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      );
    }

    // The athlete's marks: small ticks along the top.
    final tick = Paint()
      ..color = AppColors.textDim
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    for (final e in r.events) {
      canvas.drawLine(Offset(xAt(e.tS), 0), Offset(xAt(e.tS), 8), tick);
    }
  }

  @override
  bool shouldRepaint(_TimelinePainter old) => old.r != r;
}

class _EffortsCard extends StatelessWidget {
  const _EffortsCard({required this.report});

  final SessionReport report;

  @override
  Widget build(BuildContext context) {
    final r = report;
    final (color, text) = r.efforts.isEmpty
        ? (AppColors.textFaint, 'No efforts detected')
        : r.fatigueEfforts > 0
        ? (AppColors.warning, 'Fatigue building from effort ${r.efforts.firstWhere((e) => e.fatigue).number}')
        : (AppColors.good, 'No fatigue signs');
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel('Efforts', trailing: Text('${r.efforts.length}', style: AppText.dim)),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(text, style: AppText.body)),
            ],
          ),
          for (final e in r.efforts) ...[const SizedBox(height: 12), _EffortRow(effort: e)],
        ],
      ),
    );
  }
}

class _EffortRow extends StatelessWidget {
  const _EffortRow({required this.effort});

  final LiveEffort effort;

  @override
  Widget build(BuildContext context) {
    final e = effort;
    final color = e.fatigue ? AppColors.warning : AppColors.load;
    final details = [
      'peak ${e.peak.toStringAsFixed(1)}',
      if (e.hrRecoveryBpm != null) 'HR −${e.hrRecoveryBpm!.round()} in 60 s',
      if (e.peakDropPct != null && e.peakDropPct!.abs() >= 1)
        '${e.peakDropPct! > 0 ? '−' : '+'}${e.peakDropPct!.abs().round()}% vs early',
    ].join(' · ');
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.18), shape: BoxShape.circle),
          child: Text('${e.number}', style: AppText.label.copyWith(color: color, fontSize: 12)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${_mmss(e.startS)} · ${e.durationS.round()} s', style: AppText.body),
              Text(details, style: AppText.dim, maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
        if (e.fatigue) const StatusPill(color: AppColors.warning, text: 'Fatigue'),
      ],
    );
  }
}

class _QualityCard extends StatelessWidget {
  const _QualityCard({required this.report});

  final SessionReport report;

  @override
  Widget build(BuildContext context) {
    final q = report.quality;
    if (q == null) {
      return const AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionLabel('Data quality'),
            SizedBox(height: 12),
            Text('Not enough motion data in this session to judge.', style: AppText.dim),
          ],
        ),
      );
    }
    final (color, label) = switch (q.grade) {
      QualityGrade.good => (AppColors.good, 'Good'),
      QualityGrade.fair => (AppColors.warning, 'Fair'),
      QualityGrade.poor => (AppColors.danger, 'Poor'),
    };
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel(
            'Data quality',
            trailing: StatusPill(color: color, text: '$label · ${q.score}'),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _Mini(label: 'Rate', value: '${q.rateHz.round()} Hz'),
              ),
              Expanded(
                child: _Mini(label: 'Lost', value: '${q.lostPct.toStringAsFixed(1)}%'),
              ),
              Expanded(
                child: _Mini(label: 'HR cover', value: '${report.hrCoveragePct.round()}%'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (q.issues.isEmpty)
            const Text('No problems found in the recording.', style: AppText.dim)
          else
            for (final issue in q.issues)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.error_outline_rounded, size: 16, color: color),
                    const SizedBox(width: 8),
                    Expanded(child: Text(issue, style: AppText.dim)),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

class _Mini extends StatelessWidget {
  const _Mini({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: AppText.label),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value, style: AppText.stat),
        ),
      ],
    );
  }
}
