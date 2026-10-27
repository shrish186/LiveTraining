import 'package:flutter_test/flutter_test.dart';
import 'package:live_training/util/day_summary.dart';

DayEntry entry(DateTime t, {int minutes = 30, SessionSummary? summary}) => DayEntry(
  startedAt: t,
  duration: Duration(minutes: minutes),
  sport: 'soccer',
  summary: summary,
);

void main() {
  final day = DateTime(2026, 10, 27, 15);

  test('adds up only the sessions of that calendar day', () {
    final d = DaySummary.of([
      entry(DateTime(2026, 10, 26, 23, 50), summary: const SessionSummary(load: 99, efforts: 9, fatigueEfforts: 9)),
      entry(
        DateTime(2026, 10, 27, 18),
        minutes: 20,
        summary: const SessionSummary(load: 4.5, efforts: 3, fatigueEfforts: 1, hrMax: 171),
      ),
      entry(
        DateTime(2026, 10, 27, 7),
        minutes: 45,
        summary: const SessionSummary(load: 10, efforts: 6, fatigueEfforts: 0, hrMax: 182),
      ),
      entry(DateTime(2026, 10, 27, 12), minutes: 5), // recorded before summaries existed
    ], day);
    expect(d.sessions, 3);
    expect(d.entries.map((e) => e.startedAt.hour), [7, 12, 18], reason: 'oldest first');
    expect(d.trainingTime, const Duration(minutes: 70));
    expect(d.load, 14.5);
    expect(d.efforts, 9);
    expect(d.fatigueEfforts, 1);
    expect(d.fatigue, FatigueStatus.building);
    expect(d.hrMax, 182);
  });

  test('a day with no sessions', () {
    final d = DaySummary.of([], day);
    expect(d.sessions, 0);
    expect(d.load, 0);
    expect(d.fatigue, FatigueStatus.none);
    expect(d.hrMax, isNull);
  });

  test('summary JSON round trip, and missing summaries', () {
    const s = SessionSummary(load: 12.345, efforts: 4, fatigueEfforts: 2, hrAvg: 141.6, hrMax: 178.2);
    final back = SessionSummary.fromJson(s.toJson())!;
    expect(back.load, 12.3);
    expect(back.efforts, 4);
    expect(back.fatigueEfforts, 2);
    expect(back.hrAvg, 142);
    expect(back.hrMax, 178);
    expect(SessionSummary.fromJson(null), isNull);
    expect(SessionSummary.fromJson('nonsense'), isNull);
  });
}
