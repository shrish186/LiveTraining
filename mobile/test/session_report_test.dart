import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:live_training/coach/profiles.dart';
import 'package:live_training/report/session_report.dart';
import 'package:live_training/report/signal_quality.dart';

final profiles = SportProfiles.parse(File('assets/sport_profiles.yaml').readAsStringSync());
final cfg = QualityConfig.fromProfile(profiles.forSport('general'));

/// A sensor at rest for [seconds] at 100 Hz, gravity along y (same cases as analysis/tests/test_quality.py).
(List<double>, List<double>, List<double>, List<double>) still(double seconds, {double gy = 9.81, double gx = 0}) {
  final rng = math.Random(1);
  final n = (seconds * 100).round();
  double noise() => (rng.nextDouble() - 0.5) * 0.06;
  return (
    [for (var i = 0; i < n; i++) i / 100],
    [for (var i = 0; i < n; i++) gx + noise()],
    [for (var i = 0; i < n; i++) gy + noise()],
    [for (var i = 0; i < n; i++) noise()],
  );
}

void main() {
  group('signal quality', () {
    test('clean stream is good', () {
      final (t, x, y, z) = still(60);
      final q = streamQuality(t, x, y, z, cfg)!;
      expect(q.rateHz, 100);
      expect(q.gaps, 0);
      expect(q.clipLevelG, isNull);
      expect(q.gravityErrorPct, lessThan(1));
      expect(q.grade, QualityGrade.good);
      expect(q.issues, isEmpty);
    });

    test('dropout and lost samples lower the grade', () {
      final (t, x, y, z) = still(60);
      bool keep(int i) => t[i] < 20 || t[i] >= 23;
      List<double> cut(List<double> v) => [
        for (var i = 0; i < v.length; i++)
          if (keep(i)) v[i],
      ];
      final q = streamQuality(cut(t), cut(x), cut(y), cut(z), cfg)!;
      expect(q.gaps, 1);
      expect(q.longestGapS, closeTo(3.0, 0.02));
      expect(q.lostPct, closeTo(5.0, 0.3));
      expect(q.grade, isNot(QualityGrade.good));
    });

    test('clipping is found; a single real peak is not', () {
      final (t, x, y, z) = still(30);
      y[500] = 20 * 9.81;
      expect(streamQuality(t, x, y, z, cfg)!.clipLevelG, isNull);
      y[500] = 15 * 9.81;
      for (var i = 1000; i < 1012; i++) {
        y[i] = 16 * 9.81;
      }
      final q = streamQuality(t, x, y, z, cfg)!;
      expect(q.clipLevelG, closeTo(16, 0.1));
      expect(q.issues.single, contains('limit'));
    });

    test('strap moved: gravity direction changes between start and end', () {
      final (t, x, y, z) = still(40);
      for (var i = 2000; i < t.length; i++) {
        x[i] += 9.81;
        y[i] -= 9.81;
      }
      final q = streamQuality(t, x, y, z, cfg)!;
      expect(q.tiltChangeDeg, closeTo(90, 2));
      expect(q.issues.single, contains('strap'));
    });
  });

  test('report from the parity session: same efforts and fatigue as the live coach and the analysis', () {
    final expected = jsonDecode(File('test/fixtures/parity_expected.json').readAsStringSync()) as Map<String, dynamic>;
    final csv = utf8.decode(gzip.decode(File('test/fixtures/parity_session.csv.gz').readAsBytesSync()));
    final r = SessionReport.build(const LineSplitter().convert(csv), {
      'sport': expected['profile'],
      'placement': expected['placement'],
    }, profiles);

    final want = (expected['efforts'] as List).cast<Map<String, dynamic>>();
    expect(r.efforts.length, want.length);
    expect(r.efforts.map((e) => e.fatigue), want.map((w) => w['fatigue']));
    expect(r.fatigueEfforts, 2);
    expect(r.motionSource, 'phone');
    expect(r.durationS, closeTo(1860, 1));
    expect(r.motion.length, lessThanOrEqualTo(400));
    expect(r.motion.whereType<double>().reduce(math.max), greaterThan(r.effortThreshold));
    expect(r.hrMax, greaterThan(150));
    expect(r.hrCoveragePct, greaterThan(99));
    expect(r.load, greaterThan(0));
    expect(r.quality!.grade, QualityGrade.good);
    expect(r.strikes, isNull, reason: 'phone armband is not a leg placement');
    expect(r.events.map((e) => e.label), containsAll(['sync_jumps', 'drill_start']));
  });

  test('a body-worn sensor wins over the phone, and rows out of order are handled', () {
    final lines = ['t_ms,source,kind,x,y,z,value'];
    for (var ms = 0; ms < 20000; ms += 10) {
      final hard = ms >= 5000 && ms < 12000;
      lines.add('$ms,phone,acc,0,9.81,0,');
      // Watch rows arrive in 500 ms batches: written late, stamped at their own time.
      if (ms % 500 == 0 && ms > 0) {
        for (var t = ms - 500; t < ms; t += 10) {
          final strike = hard && t % 600 == 0;
          lines.add('$t,apple_watch,acc,0,${strike ? 120 : (hard ? 25 : 9.81)},0,');
        }
      }
    }
    final r = SessionReport.build(lines, {'sport': 'general', 'placement': 'ankle'}, profiles);
    expect(r.motionSource, 'apple_watch');
    expect(r.efforts.length, 1);
    expect(r.efforts.single.startS, closeTo(5, 1));
    expect(r.strikes, greaterThan(8));
    expect(r.impactLoad, greaterThan(0));
  });
}
