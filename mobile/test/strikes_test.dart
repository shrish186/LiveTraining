import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_training/coach/live_coach.dart';
import 'package:live_training/coach/profiles.dart';
import 'package:live_training/coach/strikes.dart';

/// Same signal as analysis/tests/test_steps.py `gait`: standing at 1 g, then our foot every
/// [strideS] (peak [ownG]) and the other foot halfway between (smaller).
List<(double, double)> gait(double seconds, double strideS, double ownG, double otherG) {
  const hz = 100;
  final n = (seconds * hz).round();
  final g = List<double>.filled(n, 1);
  var k = 0;
  for (var strike = 1.0; strike < seconds - 0.1; strike += strideS / 2, k++) {
    final i = (strike * hz).round();
    g[i] = k.isEven ? ownG : otherG;
    g[i - 1] = g[i + 1] = 1 + (g[i] - 1) / 2;
  }
  return [for (var i = 0; i < n; i++) (i / hz, g[i])];
}

void main() {
  test('keeps our foot, drops the other one, adds up impact load (same as the Python test)', () {
    final d = StrikeDetector(minPeakG: 2.0, minIntervalS: 0.35, weightExponent: 2);
    for (final (t, g) in gait(11, 0.6, 12, 5)) {
      d.add(t, g);
    }
    d.add(11.5, 1); // let the last strike settle
    expect(d.strikes, 17);
    expect(d.impactLoad, closeTo(17 * 12.0, 1e-9));
    expect(d.impactLoadWeighted, closeTo(17 * 144.0, 1e-9));
    expect(d.hardestG, 12);
  });

  test('standing and walking below the minimum peak are not strikes', () {
    final d = StrikeDetector(minPeakG: 2.0, minIntervalS: 0.35, weightExponent: 2);
    for (final (t, g) in gait(10, 1.1, 1.8, 1.4)) {
      d.add(t, g);
    }
    expect(d.strikes, 0);
  });

  test('the coach counts strikes only for leg placements', () {
    final profiles = SportProfiles.parse(File('assets/sport_profiles.yaml').readAsStringSync());
    final ankle = LiveCoach(CoachConfig.fromProfile(profiles.forSport('soccer'), 'ankle'));
    final pocket = LiveCoach(CoachConfig.fromProfile(profiles.forSport('soccer'), 'phone_pocket'));
    expect(pocket.strikes, isNull);
    for (final (t, g) in gait(11, 0.6, 12, 5)) {
      ankle.addAcc((t * 1000).round(), 0, g * 9.81, 0);
    }
    ankle.addAcc(11500, 0, 9.81, 0);
    expect(ankle.strikes!.strikes, 17);
  });
}
