import 'package:flutter_test/flutter_test.dart';
import 'package:live_training/coach/advice.dart';
import 'package:live_training/screens/squad_overview_card.dart';
import 'package:live_training/squad/squad_overview.dart';
import 'package:live_training/util/day_summary.dart';

final _now = DateTime(2026, 12, 10, 18);

(String, DayEntry) bowl(String who, int daysAgo, int deliveries, {double first = 17, double last = 16.5}) => (
  who,
  DayEntry(
    startedAt: DateTime(_now.year, _now.month, _now.day - daysAgo, 9),
    duration: const Duration(minutes: 60),
    sport: 'cricket',
    summary: SessionSummary(
      load: 10,
      efforts: 0,
      fatigueEfforts: 0,
      actions: deliveries,
      actionsLabel: 'deliveries',
      firstActionG: first,
      lastActionG: last,
    ),
  ),
);

void main() {
  test('steady player is on track; a delivery spike and a faded spell are flagged, flagged players first', () {
    final sessions = [
      // Arjun: 36 a week for 3 weeks, then 60 this week, last spell faded 18%.
      for (final d in [24, 22, 17, 15, 10, 8]) bowl('Arjun', d, 18),
      bowl('Arjun', 2, 30),
      bowl('Arjun', 0, 30, first: 17, last: 14),
      // Sam: steady 36 a week.
      for (final d in [24, 22, 17, 15, 10, 8, 2, 0]) bowl('Sam', d, 18),
    ];
    final o = squadOverview(sessions, _now);
    expect(o.map((p) => p.name), ['Arjun', 'Sam']);
    final arjun = o.first;
    expect(arjun.status, AdviceLevel.warn);
    expect(arjun.thisWeek.actions, 60);
    expect(arjun.usualWeeklyActions, 36);
    expect(arjun.flags.map((f) => f.text), contains('60 deliveries vs ~36 usual'));
    expect(arjun.flags.map((f) => f.text), contains('Faded 18% in last session'));
    expect(arjun.lastHeldPct!.round(), 82);
    final sam = o.last;
    expect(sam.flags.single.text, 'On track');
    expect(sam.status, AdviceLevel.good);
  });

  test('a soft start against the player\'s own usual, and a player who has not trained this week', () {
    final o = squadOverview([
      bowl('Dev', 20, 18),
      bowl('Dev', 15, 18),
      bowl('Dev', 10, 18),
      bowl('Dev', 1, 18, first: 15),
      bowl('Ravi', 12, 18),
    ], _now);
    final dev = o.firstWhere((p) => p.name == 'Dev');
    expect(dev.lastStartPct!.round(), 88);
    expect(dev.flags.map((f) => f.text), contains('Soft start: 12% below usual'));
    final ravi = o.firstWhere((p) => p.name == 'Ravi');
    expect(ravi.status, AdviceLevel.info);
    expect(ravi.flags.single.text, 'No sessions this week');
  });

  test('flags never use injury or medical wording', () {
    final o = squadOverview([
      for (final d in [22, 20, 15, 13]) bowl('A', d, 18),
      bowl('A', 0, 80, first: 17, last: 12),
    ], _now);
    for (final f in o.single.flags) {
      expect(f.text.toLowerCase(), isNot(matches(RegExp('injur|risk|diagnos|medical'))));
    }
  });
  test('the week as a CSV for the coach to send on', () {
    final csv = SquadOverviewCard.weekCsv(
      squadOverview([
        for (final d in [24, 22, 17, 15, 10, 8]) bowl('Arjun "AJ"', d, 18),
        bowl('Arjun "AJ"', 0, 60, first: 17, last: 14),
      ], _now),
    );
    final lines = csv.trim().split('\n');
    expect(lines.first, startsWith('player,sessions_7d,deliveries_7d,usual_deliveries_week'));
    expect(lines[1], startsWith('"Arjun ""AJ""",1,60,36,10.0,20.0,82,'));
  });
}
