// The live coach must agree with the offline analysis (analysis/analyze_session.py) on the same
// session. Fixture made by analysis/make_parity_fixture.py.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_training/coach/live_coach.dart';
import 'package:live_training/coach/profiles.dart';

void main() {
  test('live coach matches the Python analysis on the parity session', () {
    final expected = jsonDecode(File('test/fixtures/parity_expected.json').readAsStringSync()) as Map<String, dynamic>;
    final csv = utf8.decode(gzip.decode(File('test/fixtures/parity_session.csv.gz').readAsBytesSync()));
    final profiles = SportProfiles.parse(File('assets/sport_profiles.yaml').readAsStringSync());
    final cfg = CoachConfig.fromProfile(
      profiles.forSport(expected['profile'] as String),
      expected['placement'] as String?,
    );
    expect(cfg.profileName, expected['profile']);

    final coach = LiveCoach(cfg);
    var nextTick = 0;
    for (final line in const LineSplitter().convert(csv).skip(1)) {
      final f = line.split(',');
      final t = int.parse(f[0]);
      while (nextTick <= t) {
        coach.tick(nextTick);
        nextTick += 200;
      }
      if (f[2] == 'acc') coach.addAcc(t, double.parse(f[3]), double.parse(f[4]), double.parse(f[5]));
      if (f[2] == 'hr') coach.addHr(t, double.parse(f[6]));
    }
    coach.tick(nextTick + 120000); // let the last HR-recovery window finish

    final want = (expected['efforts'] as List).cast<Map<String, dynamic>>();
    expect(coach.efforts.length, want.length, reason: 'same number of efforts');
    for (var i = 0; i < want.length; i++) {
      final e = coach.efforts[i];
      final w = want[i];
      final label = 'effort ${i + 1}';
      // Live smoothing trails by half a window (it can't look ahead), so times may lag ~0.5 s.
      expect(e.startS, closeTo(w['start_s'] as num, 1.0), reason: '$label start');
      expect(e.endS, closeTo(w['end_s'] as num, 1.0), reason: '$label end');
      expect(e.peak, closeTo(w['peak'] as num, (w['peak'] as num) * 0.02), reason: '$label peak');
      final hrr = w['hr_recovery_bpm'] as num?;
      if (hrr == null) {
        expect(e.hrRecoveryBpm, isNull, reason: '$label HR recovery');
      } else {
        expect(e.hrRecoveryBpm, closeTo(hrr, 2.0), reason: '$label HR recovery');
      }
      expect(e.fatigue, w['fatigue'], reason: '$label fatigue flag');
    }
  });
}
