import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:live_training/coach/live_coach.dart';
import 'package:live_training/coach/profiles.dart';

final profiles = SportProfiles.parse(File('assets/sport_profiles.yaml').readAsStringSync());
CoachConfig config({String sport = 'general', String? placement = 'phone_armband'}) =>
    CoachConfig.fromProfile(profiles.forSport(sport), placement);

/// Feeds a scripted session: magnitude(t) for motion at 50 Hz, hr(t) at 1 Hz. Collects calls.
List<CoachCall> run(LiveCoach coach, double seconds, double Function(double) magnitude, double Function(double) hr) {
  final calls = <CoachCall>[...coach.start()];
  for (var ms = 0; ms <= seconds * 1000; ms += 20) {
    final t = ms / 1000;
    coach.addAcc(ms, 0, 9.81 + magnitude(t), 0); // |a| - g == magnitude exactly
    if (ms % 1000 == 0) coach.addHr(ms, hr(t));
    if (ms % 200 == 0) calls.addAll(coach.tick(ms));
  }
  return calls;
}

// A known session: 1 min standing, jog, then 6 x 20 s efforts. The last two are weaker and
// recover slower; effort 4 recovers slower but is barely weaker (must NOT be flagged).
const starts = [400.0, 560.0, 720.0, 1080.0, 1260.0, 1440.0];
const peaks = [8.0, 8.0, 8.0, 7.8, 7.2, 6.8];
const taus = [40.0, 40.0, 40.0, 70.0, 80.0, 90.0];

double magnitude(double t) {
  for (var i = 0; i < starts.length; i++) {
    if (t >= starts[i] && t < starts[i] + 20) return peaks[i];
  }
  return t < 60 ? 0.2 : 2.5;
}

double heartRate(double t) {
  if (t < 60) return 55;
  var hr = 125.0;
  for (var i = 0; i < starts.length; i++) {
    final end = starts[i] + 20;
    if (t >= starts[i] && t < end) return 125 + 50 * (t - starts[i]) / 20;
    if (t >= end) hr = 125 + 50 * math.exp(-(t - end) / taus[i]);
  }
  return hr;
}

void main() {
  test('profiles: merged over general, placement override, warm-up and readiness present', () {
    final soccer = config(sport: 'soccer', placement: 'shin');
    expect(soccer.profileName, 'soccer');
    expect(soccer.effortThreshold, 8.0);
    expect(soccer.minEffortS, 2.0);
    expect(soccer.baselineWindowS, 900);
    expect(soccer.warmupHrAboveRest, 40);
    expect(config(sport: 'curling').profileName, 'general');
    expect(config(placement: 'ankle').effortThreshold, 9.0);
  });

  test('full session: readiness, warm-up, 6 efforts, fatigue on efforts 5 and 6 only', () {
    final coach = LiveCoach(config(), restingHr: 54, recoveryScore: 78);
    final calls = run(coach, 1700, magnitude, heartRate);
    final types = calls.map((c) => c.type).toList();

    expect(calls.first.title, 'High readiness · 78%');
    final warm = calls.singleWhere((c) => c.type == CallType.warmedUp);
    expect(warm.tMs, greaterThanOrEqualTo(300000), reason: 'never before warmup.min_minutes');
    expect(warm.tMs, lessThan(400000));

    expect(types.where((t) => t == CallType.effort).length, 6);
    for (var i = 0; i < 6; i++) {
      expect(coach.efforts[i].startS, closeTo(starts[i], 1.0));
      expect(coach.efforts[i].durationS, closeTo(20, 1.0));
      expect(coach.efforts[i].peak, closeTo(peaks[i], 0.01));
    }
    expect(coach.efforts.map((e) => e.fatigue), [false, false, false, false, true, true]);
    final fatigue = calls.where((c) => c.type == CallType.fatigue).toList();
    expect(fatigue.length, 2);
    expect(fatigue.first.detail, contains('Effort 5'));
    // Called after the 60 s HR-recovery window, not before.
    expect(fatigue.first.tMs / 1000, greaterThanOrEqualTo(1260 + 20 + 60));
  });

  test('short bursts are not efforts; gaps under merge_gap join one effort', () {
    final coach = LiveCoach(config());
    run(coach, 120, (t) {
      if (t >= 10 && t < 11) return 9; // 1 s burst: shorter than min_duration_s 3 s
      if (t >= 30 && t < 36) return 9; // 6 s, then a 0.5 s dip, then 6 s more
      if (t >= 36.5 && t < 42.5) return 9;
      return 1;
    }, (t) => 100);
    expect(coach.efforts.length, 1);
    expect(coach.efforts.single.startS, closeTo(30, 1.0));
    expect(coach.efforts.single.durationS, closeTo(12.5, 1.0));
  });

  test('no fatigue call when the next effort starts inside the recovery window', () {
    final coach = LiveCoach(config());
    run(coach, 1200, (t) {
      for (final s in [100.0, 200.0, 1000.0, 1030.0]) {
        if (t >= s && t < s + 10) return 8;
      }
      return 1;
    }, (t) => 120);
    expect(coach.efforts.length, 4);
    expect(coach.efforts[2].hrRecoveryBpm, isNull);
    expect(coach.efforts.any((e) => e.fatigue), isFalse);
  });

  test('warm-up uses first-minute HR when WHOOP resting HR is unknown', () {
    final coach = LiveCoach(config());
    final calls = run(coach, 420, (t) => 1, (t) => t < 60 ? 70 : 115);
    expect(coach.warmupTargetHr, 110);
    expect(calls.where((c) => c.type == CallType.warmedUp), hasLength(1));
  });

  test('readiness bands and wording', () {
    String title(double s) => LiveCoach(config(), recoveryScore: s).start().single.title;
    expect(title(80), startsWith('High readiness'));
    expect(title(50), startsWith('Moderate readiness'));
    expect(title(20), startsWith('Low readiness'));
    expect(LiveCoach(config()).start(), isEmpty);
    for (final s in [80.0, 50.0, 20.0]) {
      final text = LiveCoach(config(), recoveryScore: s).start().single.detail.toLowerCase();
      expect(text, isNot(contains('injur')));
    }
  });
}
