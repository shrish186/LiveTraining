/// Per-session summary (saved in the session metadata at stop) and today's totals for the Home
/// screen. Pure Dart, no Flutter imports, so it is unit-testable.
library;

/// What a finished session amounted to. Stored as `summary` in the session metadata JSON.
class SessionSummary {
  const SessionSummary({
    required this.load,
    required this.efforts,
    required this.fatigueEfforts,
    this.hrAvg,
    this.hrMax,
    this.impactLoad,
    this.strikes,
    this.actions,
    this.actionsLabel,
    this.firstActionG,
    this.lastActionG,
  });

  /// Motion load, (m/s²)·min, as SessionStats.load.
  final double load;
  final int efforts;

  /// Efforts the live coach called "fatigue building".
  final int fatigueEfforts;
  final double? hrAvg;
  final double? hrMax;

  /// Sum of footstrike peaks in g, from a leg sensor (null without one).
  final double? impactLoad;
  final int? strikes;

  /// The profile's repeated big actions (e.g. 12 "deliveries"), when it defines them.
  final int? actions;
  final String? actionsLabel;

  /// Mean landing (g) of the first and last few actions: the sensor's readiness and fatigue markers.
  final double? firstActionG;
  final double? lastActionG;

  Map<String, dynamic> toJson() => {
    'load': double.parse(load.toStringAsFixed(1)),
    'efforts': efforts,
    'fatigue_efforts': fatigueEfforts,
    'hr_avg': hrAvg?.round(),
    'hr_max': hrMax?.round(),
    if (impactLoad != null) 'impact_load': impactLoad!.round(),
    if (strikes != null) 'strikes': strikes,
    if (actions != null) 'actions': actions,
    if (actionsLabel != null) 'actions_label': actionsLabel,
    if (firstActionG != null) 'first_action_g': double.parse(firstActionG!.toStringAsFixed(2)),
    if (lastActionG != null) 'last_action_g': double.parse(lastActionG!.toStringAsFixed(2)),
  };

  /// Null for sessions recorded before summaries existed (or by another device).
  static SessionSummary? fromJson(Object? j) {
    if (j is! Map) return null;
    return SessionSummary(
      load: (j['load'] as num?)?.toDouble() ?? 0,
      efforts: (j['efforts'] as num?)?.toInt() ?? 0,
      fatigueEfforts: (j['fatigue_efforts'] as num?)?.toInt() ?? 0,
      hrAvg: (j['hr_avg'] as num?)?.toDouble(),
      hrMax: (j['hr_max'] as num?)?.toDouble(),
      impactLoad: (j['impact_load'] as num?)?.toDouble(),
      strikes: (j['strikes'] as num?)?.toInt(),
      actions: (j['actions'] as num?)?.toInt(),
      actionsLabel: j['actions_label'] as String?,
      firstActionG: (j['first_action_g'] as num?)?.toDouble(),
      lastActionG: (j['last_action_g'] as num?)?.toDouble(),
    );
  }
}

/// One session as the day view needs it.
class DayEntry {
  const DayEntry({required this.startedAt, required this.duration, required this.sport, this.summary});

  final DateTime startedAt; // local time
  final Duration duration;
  final String sport;
  final SessionSummary? summary;
}

enum FatigueStatus { none, building }

/// Totals over the sessions that started on [day] (local calendar day).
class DaySummary {
  DaySummary._(this.entries);

  factory DaySummary.of(Iterable<DayEntry> all, DateTime day) {
    bool sameDay(DateTime t) => t.year == day.year && t.month == day.month && t.day == day.day;
    final today = all.where((e) => sameDay(e.startedAt)).toList()..sort((a, b) => a.startedAt.compareTo(b.startedAt));
    return DaySummary._(today);
  }

  final List<DayEntry> entries;

  int get sessions => entries.length;
  Duration get trainingTime => entries.fold(Duration.zero, (sum, e) => sum + e.duration);
  double get load => entries.fold(0.0, (sum, e) => sum + (e.summary?.load ?? 0));

  /// Null when no session today had a leg sensor.
  double? get impactLoad {
    final values = entries.map((e) => e.summary?.impactLoad).whereType<double>();
    return values.isEmpty ? null : values.reduce((a, b) => a + b);
  }

  int get efforts => entries.fold(0, (sum, e) => sum + (e.summary?.efforts ?? 0));

  /// The profile's actions today (e.g. deliveries), with their name; null when no session counted any.
  int? get actions {
    final v = entries.map((e) => e.summary?.actions).whereType<int>();
    return v.isEmpty ? null : v.reduce((a, b) => a + b);
  }

  String? get actionsLabel => entries.map((e) => e.summary?.actionsLabel).whereType<String>().lastOrNull;
  int get fatigueEfforts => entries.fold(0, (sum, e) => sum + (e.summary?.fatigueEfforts ?? 0));

  double? get hrMax {
    final values = entries.map((e) => e.summary?.hrMax).whereType<double>();
    return values.isEmpty ? null : values.reduce((a, b) => a > b ? a : b);
  }

  FatigueStatus get fatigue => fatigueEfforts > 0 ? FatigueStatus.building : FatigueStatus.none;
}

/// The athlete's usual first-actions landing (g) for [sport]: the median over their earlier sessions that
/// recorded one, or null with fewer than [minSessions] of them (median: one odd session doesn't move it).
double? actionBaseline(Iterable<DayEntry> entries, String sport, {int minSessions = 3, DateTime? before}) {
  final values = [
    for (final e in entries)
      if (e.sport == sport && e.summary?.firstActionG != null && (before == null || e.startedAt.isBefore(before)))
        e.summary!.firstActionG!,
  ]..sort();
  if (values.length < minSessions || values.isEmpty) return null;
  final m = values.length ~/ 2;
  return values.length.isOdd ? values[m] : (values[m - 1] + values[m]) / 2;
}
