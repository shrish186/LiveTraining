import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_training/coach/advice.dart';
import 'package:live_training/coach/profiles.dart';
import 'package:live_training/report/session_report.dart';
import 'package:live_training/util/day_summary.dart';
import 'package:live_training/util/trends.dart';

final _profiles = SportProfiles.parse(File('assets/sport_profiles.yaml').readAsStringSync());

SessionReport _report(String fixture, Map<String, dynamic> meta) => SessionReport.build(
  const LineSplitter().convert(utf8.decode(gzip.decode(File('test/fixtures/$fixture').readAsBytesSync()))),
  meta,
  _profiles,
);

DayEntry _day(DateTime t, double load, {int actions = 0, int fatigue = 0}) => DayEntry(
  startedAt: t,
  duration: const Duration(minutes: 60),
  sport: 'cricket',
  summary: SessionSummary(
    load: load,
    efforts: 4,
    fatigueEfforts: fatigue,
    actions: actions == 0 ? null : actions,
    actionsLabel: actions == 0 ? null : 'deliveries',
  ),
);

void main() {
  test('a spell whose last over lands softer: fatigue, where it started, what to do next time', () {
    final advice = adviceForSession(_report('spell_session.csv.gz', {'sport': 'cricket', 'placement': 'ankle'}));
    final first = advice.first;
    expect(first.level, AdviceLevel.warn);
    expect(first.title, 'Fatigue building late in the spell');
    expect(first.detail, contains('last 6 deliveries landed 19% softer'));
    expect(first.detail, contains('before number'));
    expect(advice.any((a) => a.title == 'Run-up slowed'), isTrue, reason: 'the synthetic last over has longer strides');
  });

  test('a session whose efforts faded: names the effort and what to plan next time', () {
    final advice = adviceForSession(
      _report('parity_session.csv.gz', {'sport': 'soccer', 'placement': 'phone_armband'}),
    );
    final fatigue = advice.singleWhere((a) => a.title.startsWith('Fatigue from effort'));
    expect(fatigue.level, AdviceLevel.warn);
    expect(fatigue.detail, contains('Next session, plan'));
  });

  test('no advice mentions injury or anything medical', () {
    final all = [
      ...adviceForSession(_report('spell_session.csv.gz', {'sport': 'cricket', 'placement': 'ankle'})),
      ...adviceForSession(_report('parity_session.csv.gz', {'sport': 'soccer', 'placement': 'phone_armband'})),
    ];
    for (final a in all) {
      expect('${a.title} ${a.detail}'.toLowerCase(), isNot(matches(RegExp('injur|risk|diagnos|medical'))));
    }
  });

  group('week', () {
    final today = DateTime(2026, 11, 11, 18);
    List<DayEntry> weeks(List<double> loads, {List<int>? actions}) => [
      for (var w = 0; w < 4; w++)
        for (var d = 0; d < 3; d++)
          _day(DateTime(2026, 11, 10 - 7 * (3 - w) - 2 * d, 9), loads[w] / 3, actions: (actions?[w] ?? 0) ~/ 3),
    ];

    test('a load jump says to make the next day lighter', () {
      final a = adviceForWeek(Trends.of(weeks([50, 50, 50, 110]), today));
      expect(a.first.level, AdviceLevel.warn);
      expect(a.first.title, startsWith('Load is up'));
    });

    test('steady weeks are good news', () {
      expect(adviceForWeek(Trends.of(weeks([50, 50, 50, 50]), today)).first.level, AdviceLevel.good);
    });

    test('a jump in deliveries is called out with the usual number', () {
      final a = adviceForWeek(Trends.of(weeks([50, 50, 50, 55], actions: [60, 60, 60, 120]), today));
      final d = a.singleWhere((x) => x.title.startsWith('Deliveries up'));
      expect(d.title, contains('120 this week vs about 60'));
    });

    test('new athletes are told when comparisons start', () {
      final a = adviceForWeek(Trends.of([_day(DateTime(2026, 11, 10, 9), 20)], today));
      expect(a.single.title, 'Building your baseline');
      expect(adviceForWeek(Trends.of(const [], today)), isEmpty);
    });

    test('fatigue twice and six training days', () {
      final entries = [for (var d = 0; d < 6; d++) _day(DateTime(2026, 11, 11 - d, 9), 10, fatigue: d < 2 ? 1 : 0)];
      final titles = adviceForWeek(Trends.of(entries, today)).map((a) => a.title);
      expect(titles, contains('Fatigue called 2 times this week'));
      expect(titles, contains('Trained 6 of the last 7 days'));
    });
  });
}
