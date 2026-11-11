/// The athlete's data as the AI coach sees it: a compact JSON summary built on the phone from the session
/// summaries, the trends and (when asking about one session) its report. Numbers only, rounded, no raw
/// samples and no personal details beyond the sport. Pure Dart, unit-testable.
library;

import '../report/session_report.dart';
import '../util/day_summary.dart';
import '../util/trends.dart';
import 'advice.dart';

String _date(DateTime t) =>
    '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')} '
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

double _r1(double v) => (v * 10).round() / 10;

Map<String, dynamic> _summary(SessionSummary s) => {
  'load': _r1(s.load),
  'efforts': s.efforts,
  if (s.fatigueEfforts > 0) 'fatigue_calls': s.fatigueEfforts,
  if (s.actions != null) s.actionsLabel ?? 'actions': s.actions,
  if (s.strikes != null) 'footstrikes': s.strikes,
  if (s.impactLoad != null) 'impact_load_g': s.impactLoad!.round(),
  if (s.hrAvg != null) 'hr_avg': s.hrAvg!.round(),
  if (s.hrMax != null) 'hr_max': s.hrMax!.round(),
};

/// [entries]: the athlete's own sessions (newest first or any order). [session]: the report being asked about.
Map<String, dynamic> coachContext({
  required String sport,
  required String placement,
  required Iterable<DayEntry> entries,
  required Trends trends,
  SessionReport? session,
  DateTime? sessionStartedAt,
  int maxSessions = 20,
}) {
  final recent = entries.toList()..sort((a, b) => b.startedAt.compareTo(a.startedAt));
  return {
    'sport': sport,
    'sensor_placement': placement,
    'today': _date(DateTime.now()).substring(0, 10),
    'recent_sessions': [
      for (final e in recent.take(maxSessions))
        {
          'start': _date(e.startedAt),
          'sport': e.sport,
          'minutes': e.duration.inMinutes,
          if (e.summary != null) ..._summary(e.summary!),
        },
    ],
    'weeks': [
      for (final w in trends.weeks.reversed)
        {
          'from': _date(w.start).substring(0, 10),
          'load': _r1(w.load),
          'sessions': w.sessions,
          'active_days': w.activeDays,
          'training_minutes': w.trainingTime.inMinutes,
          if (trends.actionsLabel != null) trends.actionsLabel!: w.actions,
          if (w.impactLoad != null) 'impact_load_g': w.impactLoad!.round(),
          if (w.fatigueEfforts > 0) 'fatigue_calls': w.fatigueEfforts,
        },
    ],
    if (trends.loadRatio != null) 'this_week_vs_usual_week': _r1(trends.loadRatio!),
    'app_advice_this_week': [for (final a in adviceForWeek(trends)) '${a.title}: ${a.detail}'],
    if (session != null) 'session_asked_about': _sessionDetail(session, sessionStartedAt),
  };
}

Map<String, dynamic> _sessionDetail(SessionReport r, DateTime? start) => {
  if (start != null) 'start': _date(start),
  'minutes': (r.durationS / 60).round(),
  'placement': r.placement,
  'sensor': r.motionSource,
  'load': _r1(r.load),
  if (r.hrAvg != null) 'hr_avg': r.hrAvg!.round(),
  if (r.hrMax != null) 'hr_max': r.hrMax!.round(),
  if (r.strikes != null) 'footstrikes': r.strikes,
  if (r.impactLoad != null) 'impact_load_g': r.impactLoad!.round(),
  if (r.hardestG != null) 'hardest_hit_g': _r1(r.hardestG!),
  'efforts': [
    for (final e in r.efforts)
      {
        'n': e.number,
        'start_s': e.startS.round(),
        'seconds': e.durationS.round(),
        'peak': _r1(e.peak),
        if (e.hrRecoveryBpm != null) 'hr_drop_60s': e.hrRecoveryBpm!.round(),
        if (e.peakDropPct != null) 'weaker_than_early_pct': e.peakDropPct!.round(),
        if (e.fatigue) 'fatigue': true,
      },
  ],
  if (r.actions != null)
    r.actionsLabel ?? 'actions': [
      for (final a in r.actions!)
        {
          'n': a.number,
          't_s': a.tS.round(),
          'landing_g': _r1(a.peakG),
          'runup_strides': a.runupStrikes,
          if (a.runupStrideMs != null) 'runup_stride_ms': a.runupStrideMs!.round(),
        },
    ],
  if (r.actionDriftPct != null) 'landing_last_vs_first_pct': r.actionDriftPct!.round(),
  if (r.quality != null)
    'data_quality': {
      'grade': r.quality!.grade.name,
      'score': r.quality!.score,
      'rate_hz': r.quality!.rateHz.round(),
      if (r.quality!.issues.isNotEmpty) 'issues': r.quality!.issues,
    },
  'app_advice': [for (final a in adviceForSession(r)) '${a.title}: ${a.detail}'],
};
