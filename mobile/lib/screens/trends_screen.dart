import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../coach/advice.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import '../util/trends.dart';
import 'advice_card.dart';

const _days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String _hours(Duration d) => d.inMinutes < 60 ? '${d.inMinutes}m' : '${d.inHours}h ${d.inMinutes % 60}m';

Color _trendColor(LoadTrend t) => switch (t) {
  LoadTrend.higher => AppColors.warning,
  LoadTrend.lighter => AppColors.accent,
  LoadTrend.steady => AppColors.good,
  LoadTrend.noHistory => AppColors.textDim,
};

String _trendWord(LoadTrend t) => switch (t) {
  LoadTrend.higher => 'Above usual',
  LoadTrend.lighter => 'Lighter',
  LoadTrend.steady => 'Steady',
  LoadTrend.noHistory => 'Building history',
};

/// "This week" summary at the top of the Sessions tab; opens [TrendsScreen].
class WeekCard extends StatelessWidget {
  const WeekCard({super.key, required this.trends, this.onAskCoach});

  final Trends trends;
  final VoidCallback? onAskCoach;

  @override
  Widget build(BuildContext context) {
    final w = trends.thisWeek;
    return AppCard(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => TrendsScreen(trends: trends, onAskCoach: onAskCoach),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel(
            'This week',
            trailing: StatusPill(color: _trendColor(trends.trend), text: _trendWord(trends.trend)),
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(w.load.toStringAsFixed(0), style: AppText.big),
              const SizedBox(width: 6),
              const Padding(
                padding: EdgeInsets.only(bottom: 6),
                child: Text('LOAD', style: AppText.unit),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '${w.sessions} sessions · ${_hours(w.trainingTime)}'
                  '${trends.actionsLabel != null ? ' · ${w.actions} ${trends.actionsLabel}' : ''}',
                  style: AppText.dim,
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(height: 56, child: LoadBars(days: trends.days.sublist(trends.days.length - 7), labels: true)),
          const SizedBox(height: 4),
          const Align(
            alignment: Alignment.centerRight,
            child: Text('4-week trends ›', style: AppText.dim),
          ),
        ],
      ),
    );
  }
}

/// Daily load bars, the last bar (today) highlighted.
class LoadBars extends StatelessWidget {
  const LoadBars({super.key, required this.days, this.labels = false, this.average});

  final List<DayTotals> days;
  final bool labels;

  /// Average daily load, drawn as a dashed line.
  final double? average;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _BarsPainter(days, labels, average), child: const SizedBox.expand());
}

class _BarsPainter extends CustomPainter {
  _BarsPainter(this.days, this.labels, this.average);

  final List<DayTotals> days;
  final bool labels;
  final double? average;

  @override
  void paint(Canvas canvas, Size size) {
    final labelH = labels ? 14.0 : 0.0;
    final h = size.height - labelH;
    final top = math.max(days.fold(0.0, (m, d) => math.max(m, d.load)), average ?? 0);
    final slot = size.width / days.length;
    final barW = math.min(slot * 0.6, 18.0);
    for (var i = 0; i < days.length; i++) {
      final d = days[i];
      final x = slot * i + (slot - barW) / 2;
      final bh = top <= 0 ? 0.0 : math.max(d.sessions > 0 ? 3.0 : 0.0, d.load / top * (h - 4));
      final color = i == days.length - 1 ? AppColors.load : AppColors.load.withValues(alpha: 0.45);
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(x, h - bh, barW, bh), const Radius.circular(3)),
        Paint()..color = d.sessions > 0 ? color : AppColors.surfaceHigh,
      );
      if (d.sessions == 0) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(x, h - 3, barW, 3), const Radius.circular(2)),
          Paint()..color = AppColors.surfaceHigh,
        );
      }
      if (labels) {
        final tp = TextPainter(
          text: TextSpan(
            text: _days[d.day.weekday - 1],
            style: const TextStyle(fontSize: 10, color: AppColors.textFaint),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(slot * i + (slot - tp.width) / 2, h + 2));
      }
    }
    final avg = average;
    if (avg != null && top > 0) {
      final y = h - avg / top * (h - 4);
      final p = Paint()
        ..color = AppColors.textDim
        ..strokeWidth = 1;
      for (var x = 0.0; x < size.width; x += 8) {
        canvas.drawLine(Offset(x, y), Offset(math.min(x + 4, size.width), y), p);
      }
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) => old.days != days || old.average != average;
}

/// Four weeks of training: daily load, this week against the athlete's own average, weekly totals.
class TrendsScreen extends StatelessWidget {
  const TrendsScreen({super.key, required this.trends, this.onAskCoach, this.title = 'Trends'});

  final Trends trends;
  final String title;
  final VoidCallback? onAskCoach;

  @override
  Widget build(BuildContext context) {
    final t = trends;
    final w = t.thisWeek;
    final label = t.actionsLabel;
    final tiles = [
      StatTile(label: 'Sessions', value: '${w.sessions}', color: AppColors.accent),
      StatTile(label: 'Training time', value: _hours(w.trainingTime)),
      StatTile(label: 'Active days', value: '${w.activeDays}', unit: '/ 7'),
      StatTile(
        label: 'Fatigue calls',
        value: '${w.fatigueEfforts}',
        color: w.fatigueEfforts > 0 ? AppColors.warning : null,
      ),
      if (w.impactLoad != null) StatTile(label: 'Impact load', value: w.impactLoad!.round().toString(), unit: 'g'),
      if (label != null)
        StatTile(label: label[0].toUpperCase() + label.substring(1), value: '${w.actions}', color: AppColors.accent),
    ];
    final advice = adviceForWeek(t);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          if (advice.isNotEmpty || onAskCoach != null) ...[
            AdviceCard(
              title: 'This week',
              advice: advice,
              action: onAskCoach == null
                  ? null
                  : SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: onAskCoach,
                        icon: const Icon(Icons.forum_outlined),
                        label: const Text('Ask the coach'),
                      ),
                    ),
            ),
            const SizedBox(height: 12),
          ],
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionLabel(
                  'Load, last 7 days',
                  trailing: StatusPill(color: _trendColor(t.trend), text: _trendWord(t.trend)),
                ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(w.load.toStringAsFixed(0), style: AppText.big),
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text('usual week ${t.averageWeekLoad.toStringAsFixed(0)}', style: AppText.dim),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(t.headline, style: AppText.body),
              ],
            ),
          ),
          const SizedBox(height: 12),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionLabel('Daily load, 4 weeks'),
                const SizedBox(height: 12),
                SizedBox(
                  height: 120,
                  child: LoadBars(days: t.days, average: t.averageWeekLoad / 7),
                ),
                const SizedBox(height: 6),
                const Text('Dashed line: your average day.', style: AppText.dim),
              ],
            ),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < tiles.length; i += 2) ...[
            Row(
              children: [
                Expanded(child: tiles[i]),
                const SizedBox(width: 10),
                Expanded(child: i + 1 < tiles.length ? tiles[i + 1] : const SizedBox()),
              ],
            ),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 2),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionLabel('Weeks'),
                const SizedBox(height: 8),
                for (final wk in t.weeks.reversed)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            identical(wk, t.weeks.last)
                                ? 'This week'
                                : 'From ${wk.start.day} ${_months[wk.start.month - 1]}',
                            style: AppText.body,
                          ),
                        ),
                        Flexible(
                          child: Text(
                            '${wk.load.toStringAsFixed(0)} load · ${wk.sessions} sessions'
                            '${label != null ? ' · ${wk.actions} $label' : ''}',
                            style: AppText.dim,
                            textAlign: TextAlign.right,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
