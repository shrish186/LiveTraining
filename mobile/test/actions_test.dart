import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:live_training/coach/actions.dart';
import 'package:live_training/coach/live_coach.dart';
import 'package:live_training/coach/profiles.dart';

const cfg = ActionConfig(
  label: 'delivery',
  labelPlural: 'deliveries',
  minPeakG: 8,
  minRatio: 1.4,
  runupWindowS: 6,
  minRunupStrikes: 4,
  minGapS: 15,
  maxStrideS: 1.5,
  compare: 3,
);

/// Same strikes as analysis/tests/test_actions.py `spell`: run-up, landing spike, follow-through, walk back.
List<(double, double)> spell(List<double> spikes, {double runupG = 5, double strideS = 0.65}) {
  final out = <(double, double)>[];
  var t = 10.0;
  for (final spike in spikes) {
    for (var i = 0; i < 8; i++) {
      out.add((t + i * strideS, runupG));
    }
    t += 8 * strideS;
    out
      ..add((t, spike))
      ..add((t + 0.6, 6))
      ..add((t + 1.2, 4));
    for (var i = 0; i < 20; i++) {
      out.add((t + 3 + i * 1.1, 2.5));
    }
    t += 3 + 20 * 1.1 + 10;
  }
  return out;
}

ActionDetector run(List<(double, double)> strikes) {
  final d = ActionDetector(cfg);
  for (final (t, g) in strikes) {
    d
      ..addStrike(t, g)
      ..tick(t);
  }
  d.finish();
  return d;
}

void main() {
  test('counts each delivery once (same as the Python test)', () {
    final d = run(spell([14, 15, 13, 14, 16, 14]));
    expect(d.actions.map((a) => a.peakG), [14, 15, 13, 14, 16, 14]);
    expect(d.actions.map((a) => a.number), [1, 2, 3, 4, 5, 6]);
    expect(d.actions.every((a) => a.runupStrikes >= 4 && (a.runupStrideMs! - 650).abs() < 1), isTrue);
  });

  test('a sprint without a spike and a big hit without a run-up are not actions', () {
    expect(run([for (var i = 0; i < 20; i++) (5 + i * 0.6, 12.0 + i % 3)]).actions, isEmpty);
    expect(run([(5, 2), (20, 15)]).actions, isEmpty);
  });

  test('softer landings late in the spell show as drift', () {
    final d = run(spell([15, 15, 15, 12, 12, 12]));
    expect(d.peakDriftPct!.round(), -20);
    expect(run(spell([15, 15, 15, 12, 12])).peakDriftPct, isNull);
  });

  test('the cricket coach calls each delivery and the fatigue from softer landings', () {
    final profiles = SportProfiles.parse(File('assets/sport_profiles.yaml').readAsStringSync());
    final coach = LiveCoach(CoachConfig.fromProfile(profiles.forSport('cricket'), 'ankle'));
    expect(LiveCoach(CoachConfig.fromProfile(profiles.forSport('cricket'), 'waist')).actions, isNull);
    expect(LiveCoach(CoachConfig.fromProfile(profiles.forSport('soccer'), 'ankle')).actions, isNull);

    // 12 deliveries 40 s apart, as a raw 100 Hz signal; the last 6 land 20% softer.
    final spikes = <double, double>{};
    for (var k = 0; k < 12; k++) {
      final s0 = 20.0 + 40 * k;
      for (var i = 0; i < 8; i++) {
        spikes[s0 + i * 0.65] = 5;
      }
      spikes[s0 + 8 * 0.65] = k < 6 ? 15 : 12;
      spikes[s0 + 8 * 0.65 + 0.6] = 6;
    }
    final calls = <CoachCall>[];
    for (var ms = 0; ms < 520000; ms += 10) {
      final t = ms / 1000;
      var g = 1.0;
      for (final e in spikes.entries) {
        if ((t - e.key).abs() < 0.05) g += (e.value - 1) * math.exp(-math.pow((t - e.key) / 0.012, 2));
      }
      coach.addAcc(ms, 0, g * 9.81, 0);
      if (ms % 200 == 0) calls.addAll(coach.tick(ms));
    }
    calls.addAll(coach.finish());
    final deliveries = calls.where((c) => c.type == CallType.action).toList();
    expect(deliveries, hasLength(12));
    expect(deliveries.first.title, startsWith('Delivery 1 · 15'));
    expect(deliveries.first.eventLabel, 'call_action');
    final fatigue = calls.where((c) => c.type == CallType.fatigue).toList();
    expect(fatigue, hasLength(1));
    expect(fatigue.single.detail, contains('last 6 deliveries landed 20% softer'));
  });

  test('readiness from the sensor: the first over against the usual first over', () {
    final profiles = SportProfiles.parse(File('assets/sport_profiles.yaml').readAsStringSync());
    final cfg = CoachConfig.fromProfile(profiles.forSport('cricket'), 'ankle');
    expect(cfg.actions!.readinessDropPct, 8);
    expect(cfg.actions!.baselineSessions, 3);

    List<CoachCall> bowlSpell(double? usual) {
      final coach = LiveCoach(cfg, actionBaselineG: usual);
      final calls = <CoachCall>[];
      // 6 deliveries landing at 15 g, 40 s apart, run-up strides at 5 g (as raw 100 Hz samples).
      final spikes = <double, double>{};
      for (var k = 0; k < 6; k++) {
        final s0 = 20.0 + 40 * k;
        for (var i = 0; i < 8; i++) {
          spikes[s0 + i * 0.65] = 5;
        }
        spikes[s0 + 8 * 0.65] = 15;
      }
      for (var ms = 0; ms < 280000; ms += 10) {
        final t = ms / 1000;
        var g = 1.0;
        for (final e in spikes.entries) {
          if ((t - e.key).abs() < 0.05) g += (e.value - 1) * math.exp(-math.pow((t - e.key) / 0.012, 2));
        }
        coach.addAcc(ms, 0, g * 9.81, 0);
        if (ms % 200 == 0) calls.addAll(coach.tick(ms));
      }
      calls.addAll(coach.finish());
      expect(coach.actions!.firstPeakG, closeTo(15, 0.2));
      return calls.where((c) => c.type == CallType.readiness).toList();
    }

    final soft = bowlSpell(17.0);
    expect(soft.single.title, startsWith('Soft start · 12% below your usual'));
    expect(bowlSpell(14.0).single.title, startsWith('Sharp start'));
    expect(bowlSpell(15.2), isEmpty, reason: 'a normal start stays quiet');
    expect(bowlSpell(null), isEmpty, reason: 'no history: nothing to compare with');
  });
}
