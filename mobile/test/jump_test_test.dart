import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_training/coach/profiles.dart';
import 'package:live_training/readiness/jump_test.dart';

final _cfg = JumpConfig.fromProfile(
  SportProfiles.parse(File('assets/sport_profiles.yaml').readAsStringSync()).forSport('cricket'),
);

void main() {
  test('finds the same jumps as the Python analysis (analysis/make_parity_fixture.py)', () {
    final rows = File('test/fixtures/jumps_signal.csv').readAsLinesSync().skip(1).map((l) => l.split(','));
    final t = [for (final r in rows) double.parse(r[0])];
    final g = [for (final r in rows) double.parse(r[1])];
    final want = (jsonDecode(File('test/fixtures/jumps_expected.json').readAsStringSync())['jumps'] as List)
        .cast<Map<String, dynamic>>();
    final got = detectJumps(t, g, _cfg);
    expect(got.length, want.length);
    for (var i = 0; i < want.length; i++) {
      expect(got[i].takeoffS, closeTo(want[i]['takeoff_s'] as num, 1e-6));
      expect(got[i].landingS, closeTo(want[i]['landing_s'] as num, 1e-6));
      expect(got[i].heightCm, closeTo(want[i]['height_cm'] as num, 1e-3));
    }
  });

  test('profile: three jumps, compared after three earlier checks', () {
    expect(_cfg.jumps, 3);
    expect(_cfg.baselineTests, 3);
    expect(_cfg.belowUsualPct, 6);
  });

  test('score is the mean of the two best jumps', () {
    final r = JumpTestResult(DateTime(2026, 11, 12, 7), const [20, 30, 28]);
    expect(r.scoreCm, 29);
    expect(r.bestCm, 30);
  });

  group('verdict against your usual', () {
    JumpTestResult check(int day, double cm, {String source = 'sensor'}) =>
        JumpTestResult(DateTime(2026, 11, day, 7), [cm, cm], source: source);
    final history = [check(1, 30), check(2, 31), check(3, 29), check(4, 50, source: 'phone')];

    test('needs three earlier checks from the same source', () {
      expect(jumpVerdict(check(5, 30), history.take(2).toList(), _cfg).state, JumpReadiness.noBaseline);
      expect(jumpVerdict(check(5, 30, source: 'phone'), history, _cfg).state, JumpReadiness.noBaseline);
    });

    test('below, normal and above', () {
      final low = jumpVerdict(check(5, 27), history, _cfg);
      expect(low.state, JumpReadiness.below);
      expect(low.usualCm, 30);
      expect(low.advice, contains('10% lower than usual'));
      expect(jumpVerdict(check(5, 29.5), history, _cfg).state, JumpReadiness.normal);
      expect(jumpVerdict(check(5, 32), history, _cfg).state, JumpReadiness.above);
    });

    test('wording stays on readiness', () {
      for (final cm in [20.0, 30.0, 40.0]) {
        final v = jumpVerdict(check(5, cm), history, _cfg);
        expect('${v.title} ${v.advice}'.toLowerCase(), isNot(matches(RegExp('injur|risk|diagnos|medical'))));
      }
    });
  });

  test('results survive storage, bad data is ignored', () {
    final all = [
      JumpTestResult(DateTime(2026, 11, 12, 7, 5), const [24.31, 26.0], source: 'phone'),
    ];
    final back = JumpTestResult.decodeAll(JumpTestResult.encodeAll(all));
    expect(back.single.heightsCm, [24.3, 26.0]);
    expect(back.single.source, 'phone');
    expect(JumpTestResult.decodeAll('not json'), isEmpty);
    expect(JumpTestResult.decodeAll('[{"at": "x"}]'), isEmpty);
  });

  test('a check in progress finds the jumps and stops after the third', () {
    final rows = File('test/fixtures/jumps_signal.csv').readAsLinesSync().skip(1).map((l) => l.split(','));
    final run = JumpTestRun(_cfg, 'sensor', 1000);
    var finishedAt = -1.0;
    for (final r in rows) {
      final t = double.parse(r[0]);
      run.add(1000 + (t * 1000).round(), double.parse(r[1]));
      if (finishedAt < 0 && run.update(1000 + (t * 1000).round())) finishedAt = t;
    }
    expect(run.done, isTrue);
    expect(run.timedOut, isFalse);
    expect(finishedAt, greaterThan(12.4), reason: 'the third jump lands at 12.45 s and must settle first');
    expect(run.result!.heightsCm.map((h) => h.round()), [22, 28, 25]);
    expect(run.result!.scoreCm, closeTo((28.347 + 25.042) / 2, 0.1)); // live timestamps are whole ms
  });

  test('a check with no jumps times out with no result', () {
    final run = JumpTestRun(_cfg, 'phone', 0);
    for (var ms = 0; ms <= 41000; ms += 10) {
      run.add(ms, 1.0);
      run.update(ms);
      if (run.done) break;
    }
    expect(run.done && run.timedOut, isTrue);
    expect(run.result, isNull);
  });
}
