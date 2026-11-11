/// Training trends over the last weeks, from the per-session summaries: daily load, this week
/// against the athlete's own 4-week average, and the profile's actions (e.g. deliveries) per week.
/// Pure Dart, no Flutter imports, so it is unit-testable.
///
/// Wording rule: this describes load ("this week is 40% above your 4-week average"). It does not
/// predict anything medical.
library;

import 'day_summary.dart';

class DayTotals {
  DayTotals(this.day);

  final DateTime day; // local midnight
  double load = 0;
  int sessions = 0;
  Duration trainingTime = Duration.zero;
  double? impactLoad;
  int actions = 0;
  int fatigueEfforts = 0;
}

class WeekTotals {
  WeekTotals(this.days);

  /// 7 days, oldest first.
  final List<DayTotals> days;

  DateTime get start => days.first.day;
  double get load => days.fold(0.0, (s, d) => s + d.load);
  int get sessions => days.fold(0, (s, d) => s + d.sessions);
  Duration get trainingTime => days.fold(Duration.zero, (s, d) => s + d.trainingTime);
  int get actions => days.fold(0, (s, d) => s + d.actions);
  int get fatigueEfforts => days.fold(0, (s, d) => s + d.fatigueEfforts);
  int get activeDays => days.where((d) => d.sessions > 0).length;

  double? get impactLoad {
    final v = days.map((d) => d.impactLoad).whereType<double>();
    return v.isEmpty ? null : v.reduce((a, b) => a + b);
  }
}

enum LoadTrend { noHistory, lighter, steady, higher }

class Trends {
  Trends._(this.days, this.actionsLabel, this.historyDays);

  /// The last [weeks] × 7 days up to and including [today], oldest first. Each week ends on [today]'s
  /// weekday, so "this week" is always the last 7 days.
  factory Trends.of(Iterable<DayEntry> entries, DateTime today, {int weeks = 4}) {
    final end = DateTime(today.year, today.month, today.day);
    final days = [for (var i = weeks * 7 - 1; i >= 0; i--) DayTotals(DateTime(end.year, end.month, end.day - i))];
    final index = {for (var i = 0; i < days.length; i++) days[i].day: i};
    String? label;
    DateTime? earliest;
    for (final e in entries) {
      final d = DateTime(e.startedAt.year, e.startedAt.month, e.startedAt.day);
      if (earliest == null || d.isBefore(earliest)) earliest = d;
      final i = index[d];
      if (i == null) continue;
      final t = days[i]
        ..sessions += 1
        ..trainingTime += e.duration;
      final s = e.summary;
      if (s == null) continue;
      t
        ..load += s.load
        ..fatigueEfforts += s.fatigueEfforts
        ..actions += s.actions ?? 0;
      if (s.impactLoad != null) t.impactLoad = (t.impactLoad ?? 0) + s.impactLoad!;
      if (s.actionsLabel != null) label = s.actionsLabel;
    }
    final history = earliest == null ? 0 : end.difference(earliest).inDays + 1;
    return Trends._(days, label, history);
  }

  final List<DayTotals> days;

  /// e.g. "deliveries", when any session in range counted the profile's actions.
  final String? actionsLabel;

  /// Days since the first recorded session (inclusive).
  final int historyDays;

  List<WeekTotals> get weeks => [for (var i = 0; i < days.length; i += 7) WeekTotals(days.sublist(i, i + 7))];

  WeekTotals get thisWeek => weeks.last;

  /// Average weekly load over the whole range (4 weeks by default), this week included.
  double get averageWeekLoad => weeks.fold(0.0, (s, w) => s + w.load) / weeks.length;

  /// This week's load against the average week, e.g. 1.4 = 40% above. Null without 3 weeks of history
  /// (the average would mostly be days before the athlete started).
  double? get loadRatio {
    final avg = averageWeekLoad;
    if (historyDays < 21 || avg <= 0) return null;
    return thisWeek.load / avg;
  }

  LoadTrend get trend {
    final r = loadRatio;
    if (r == null) return LoadTrend.noHistory;
    if (r > 1.3) return LoadTrend.higher;
    if (r < 0.8) return LoadTrend.lighter;
    return LoadTrend.steady;
  }

  /// One line for the athlete.
  String get headline {
    final r = loadRatio;
    return switch (trend) {
      LoadTrend.noHistory => 'Keep recording: the comparison with your usual week starts after 3 weeks.',
      LoadTrend.higher => 'This week is ${((r! - 1) * 100).round()}% above your 4-week average. Build up gradually.',
      LoadTrend.lighter => 'This week is ${((1 - r!) * 100).round()}% below your 4-week average.',
      LoadTrend.steady => 'This week is in line with your 4-week average.',
    };
  }
}
