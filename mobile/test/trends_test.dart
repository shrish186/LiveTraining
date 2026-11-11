import 'package:flutter_test/flutter_test.dart';
import 'package:live_training/util/day_summary.dart';
import 'package:live_training/util/trends.dart';

DayEntry entry(DateTime at, double load, {int actions = 0, double? impact, int fatigue = 0}) => DayEntry(
  startedAt: at,
  duration: const Duration(minutes: 60),
  sport: 'cricket',
  summary: SessionSummary(
    load: load,
    efforts: 3,
    fatigueEfforts: fatigue,
    impactLoad: impact,
    actions: actions == 0 ? null : actions,
    actionsLabel: actions == 0 ? null : 'deliveries',
  ),
);

void main() {
  final today = DateTime(2026, 11, 11, 18);

  test('days, weeks and totals; this week is the last 7 days', () {
    final t = Trends.of([
      entry(DateTime(2026, 11, 11, 7), 20, actions: 36, impact: 900, fatigue: 1),
      entry(DateTime(2026, 11, 11, 17), 10),
      entry(DateTime(2026, 11, 5, 9), 30, actions: 24), // 6 days ago: this week
      entry(DateTime(2026, 11, 4, 9), 40), // 7 days ago: last week
      entry(DateTime(2026, 10, 1, 9), 99), // outside the 4 weeks
    ], today);
    expect(t.days, hasLength(28));
    expect(t.days.last.day, DateTime(2026, 11, 11));
    expect(t.days.last.sessions, 2);
    expect(t.days.last.load, 30);
    expect(t.thisWeek.load, 60);
    expect(t.thisWeek.actions, 60);
    expect(t.thisWeek.activeDays, 2);
    expect(t.thisWeek.impactLoad, 900);
    expect(t.thisWeek.fatigueEfforts, 1);
    expect(t.weeks[2].load, 40);
    expect(t.actionsLabel, 'deliveries');
    expect(t.averageWeekLoad, 25);
    expect(t.loadRatio, closeTo(2.4, 1e-9)); // history since Oct 1
    expect(t.trend, LoadTrend.higher);
    expect(t.headline, contains('140% above'));
  });

  test('no comparison before 3 weeks of history', () {
    final t = Trends.of([entry(DateTime(2026, 11, 1, 9), 30), entry(DateTime(2026, 11, 10, 9), 30)], today);
    expect(t.loadRatio, isNull);
    expect(t.trend, LoadTrend.noHistory);
    expect(t.actionsLabel, isNull);
  });

  test('steady and lighter weeks', () {
    List<DayEntry> weekly(List<double> loads) => [
      for (var w = 0; w < 4; w++) entry(DateTime(2026, 11, 10 - 7 * (3 - w), 9), loads[w]),
    ];
    expect(Trends.of(weekly([50, 50, 50, 50]), today).trend, LoadTrend.steady);
    final light = Trends.of(weekly([60, 60, 60, 20]), today);
    expect(light.trend, LoadTrend.lighter);
    expect(light.headline, contains('% below'));
  });
}
