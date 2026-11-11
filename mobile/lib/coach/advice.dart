/// Plain-language advice from what the app has already measured: one session (its report) and the
/// last weeks (trends). Rules only, no model, so it works offline and every line can be traced to a
/// number on screen. Pure Dart, unit-testable.
///
/// Wording rule (CLAUDE.md): load, fatigue, readiness. Never injury prediction or a medical claim.
library;

import '../report/session_report.dart';
import '../report/signal_quality.dart';
import '../util/trends.dart';

enum AdviceLevel { good, info, warn }

class Advice {
  const Advice(this.level, this.title, this.detail);

  final AdviceLevel level;
  final String title;
  final String detail;

  @override
  String toString() => '[$level] $title: $detail';
}

String _pct(double v) => '${v.abs().round()}%';
String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
double _mean(Iterable<double> v) => v.reduce((a, b) => a + b) / v.length;

/// Advice after one session, most important first.
List<Advice> adviceForSession(SessionReport r) {
  final out = <Advice>[];

  // 1. Data first: advice from a bad recording would be wrong.
  final q = r.quality;
  if (q != null && q.grade != QualityGrade.good) {
    final tips = <String>[
      if (q.issues.any((i) => i.contains('missing') || i.contains('dropout')))
        'keep the phone within a few metres of the sensor, on the same side of the body',
      if (q.clipLevelG != null) 'hard landings went past the sensor\'s range: check the high-g sensor is connected',
      if (q.issues.any((i) => i.contains('gravity'))) 'lay the sensor still on a table for 10 s before strapping it on',
      if (q.issues.any((i) => i.contains('strap'))) 'tighten the strap so the sensor can\'t turn on the leg',
    ];
    out.add(
      Advice(
        AdviceLevel.warn,
        'Check the recording before trusting these numbers',
        '${q.issues.join('; ')}.${tips.isEmpty ? '' : ' Next time: ${tips.join('; ')}.'}',
      ),
    );
  }

  // 2. Repeated actions (e.g. deliveries): do the landings hold up through the spell?
  final actions = r.actions;
  final n = r.actionsCompare;
  if (actions != null && r.actionsLabel != null && n > 0) {
    final plural = r.actionsLabel!;
    final drift = r.actionDriftPct;
    if (actions.isEmpty) {
      // Nothing detected: only worth saying if the sensor was on a leg (the list exists).
    } else if (drift == null) {
      out.add(
        Advice(
          AdviceLevel.info,
          '${actions.length} $plural recorded',
          'Do at least ${2 * n} in a session to see whether your landings hold up from start to finish.',
        ),
      );
    } else {
      final first = _mean(actions.take(n).map((a) => a.peakG));
      final last = _mean(actions.skip(actions.length - n).map((a) => a.peakG));
      if (drift <= -10) {
        // Where did it start: the first one 10% below the opening average, after the opening group.
        final turn = actions.skip(n).where((a) => a.peakG < first * 0.9).map((a) => a.number).firstOrNull;
        out.add(
          Advice(
            AdviceLevel.warn,
            'Fatigue building late in the spell',
            'Your last $n $plural landed ${_pct(drift)} softer than your first $n '
                '(${last.toStringAsFixed(1)} g vs ${first.toStringAsFixed(1)} g).'
                '${turn == null ? '' : ' The drop started around number $turn.'} '
                '${turn == null ? 'Next time, plan a break after ${actions.length - n} $plural.' : 'Next time, plan a break or end the spell before number $turn.'}',
          ),
        );
      } else {
        out.add(
          Advice(
            AdviceLevel.good,
            'Landings held up',
            'Your last $n $plural were within ${_pct(drift)} of your first $n: this spell length suited you today.',
          ),
        );
      }
      final s0 = actions.take(n).map((a) => a.runupStrideMs).whereType<double>();
      final s1 = actions.skip(actions.length - n).map((a) => a.runupStrideMs).whereType<double>();
      if (s0.isNotEmpty && s1.isNotEmpty && _mean(s1) - _mean(s0) >= 40) {
        out.add(
          Advice(
            AdviceLevel.info,
            'Run-up slowed',
            'Run-up strides were ${(_mean(s1) - _mean(s0)).round()} ms longer at the end than at the start. '
                'A slower approach is an early sign of tiredness: keep the rhythm, or shorten the spell.',
          ),
        );
      }
    }
  }

  // 3. Efforts: did they fade?
  final fatigued = r.efforts.where((e) => e.fatigue).toList();
  if (fatigued.isNotEmpty) {
    final e = fatigued.first;
    out.add(
      Advice(
        AdviceLevel.warn,
        'Fatigue from effort ${e.number}',
        'Effort ${e.number} was ${_pct(e.peakDropPct ?? 0)} weaker than your early efforts and your heart rate '
            'came down slower. Next session, plan ${e.number - 1} hard efforts at this intensity, or take longer '
            'rests between them.',
      ),
    );
  } else if (r.efforts.length >= 3 && r.efforts.any((e) => e.assessed)) {
    out.add(
      Advice(
        AdviceLevel.good,
        'Efforts held up',
        'No drop in your ${r.efforts.length} efforts: you can add one more next time, or keep the session and '
            'push the pace.',
      ),
    );
  }

  if (out.isEmpty && r.durationS < 120) {
    out.add(
      const Advice(AdviceLevel.info, 'Short session', 'Under two minutes recorded: record a full session for advice.'),
    );
  }
  return out;
}

/// Advice for the week, from the last 4 weeks of sessions, most important first.
List<Advice> adviceForWeek(Trends t) {
  final out = <Advice>[];
  final w = t.thisWeek;
  final ratio = t.loadRatio;

  switch (t.trend) {
    case LoadTrend.higher:
      out.add(
        Advice(
          AdviceLevel.warn,
          'Load is up ${_pct((ratio! - 1) * 100)} on your usual week',
          'Make the next day lighter (technique, mobility or rest). Steady build-ups are easier to absorb '
              'than big jumps from one week to the next.',
        ),
      );
    case LoadTrend.lighter:
      out.add(
        Advice(
          AdviceLevel.info,
          'Lighter week (${_pct((1 - ratio!) * 100)} below usual)',
          'Good for recovering. To keep building, add a session at your usual intensity.',
        ),
      );
    case LoadTrend.steady:
      out.add(
        const Advice(
          AdviceLevel.good,
          'Load in line with your usual week',
          'Consistent weeks are what build fitness. Keep the plan.',
        ),
      );
    case LoadTrend.noHistory:
      if (t.historyDays > 0) {
        out.add(
          Advice(
            AdviceLevel.info,
            'Building your baseline',
            'After 3 weeks of sessions (${t.historyDays} day${t.historyDays == 1 ? '' : 's'} so far), each week is '
                'compared with your usual one.',
          ),
        );
      }
  }

  // Repeated actions (e.g. deliveries): this week against the earlier weeks that had any.
  final label = t.actionsLabel;
  if (label != null) {
    final earlier = t.weeks.take(t.weeks.length - 1).map((wk) => wk.actions).where((a) => a > 0).toList();
    if (earlier.isNotEmpty) {
      final usual = earlier.reduce((a, b) => a + b) / earlier.length;
      if (usual >= 6 && w.actions > usual * 1.3) {
        out.add(
          Advice(
            AdviceLevel.warn,
            '${_cap(label)} up: ${w.actions} this week vs about ${usual.round()} usually',
            'Build $label volume in small steps from week to week rather than in one jump.',
          ),
        );
      }
    }
  }

  if (w.fatigueEfforts >= 2) {
    out.add(
      Advice(
        AdviceLevel.warn,
        'Fatigue called ${w.fatigueEfforts} times this week',
        'Put an easy day before your next hard session.',
      ),
    );
  }
  if (w.activeDays >= 6) {
    out.add(
      Advice(AdviceLevel.info, 'Trained ${w.activeDays} of the last 7 days', 'Plan at least one full rest day a week.'),
    );
  }
  return out;
}
