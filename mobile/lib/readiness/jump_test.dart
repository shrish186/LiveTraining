/// Daily readiness check: three countermovement jumps, height from flight time. A port of
/// analysis/ltlib/steps.py `detect_jumps` (same rule, same profile `jumps` block), plus the test's scoring
/// against the athlete's own earlier tests (profile `jump_test` block). Pure Dart, unit-testable.
///
/// Jump height is a long-standing readiness marker in sport science: a tired athlete jumps lower than
/// usual. Wording rule: readiness and fatigue only, never an injury or medical claim.
library;

import 'dart:convert';
import 'dart:math' as math;

const _gravity = 9.81;

class JumpConfig {
  const JumpConfig({
    required this.takeoffG,
    required this.flightBelowG,
    required this.landingAboveG,
    required this.landingPeakG,
    required this.minFlightS,
    required this.maxFlightS,
    required this.quietS,
    required this.quietStdG,
    required this.jumps,
    required this.maxSeconds,
    required this.belowUsualPct,
    required this.aboveUsualPct,
    required this.baselineTests,
  });

  /// From a merged sport profile (its `jumps` and `jump_test` blocks).
  factory JumpConfig.fromProfile(Map<String, dynamic> profile) {
    final j = profile['jumps'] as Map<String, dynamic>;
    final t = (profile['jump_test'] as Map<String, dynamic>?) ?? const {};
    double n(Map<String, dynamic> m, String k, [double? fallback]) => (m[k] as num?)?.toDouble() ?? fallback!;
    return JumpConfig(
      takeoffG: n(j, 'takeoff_g'),
      flightBelowG: n(j, 'flight_below_g'),
      landingAboveG: n(j, 'landing_above_g'),
      landingPeakG: n(j, 'landing_peak_g'),
      minFlightS: n(j, 'min_flight_s'),
      maxFlightS: n(j, 'max_flight_s'),
      quietS: n(j, 'quiet_s'),
      quietStdG: n(j, 'quiet_std_g'),
      jumps: n(t, 'jumps', 3).round(),
      maxSeconds: n(t, 'max_seconds', 40),
      belowUsualPct: n(t, 'below_usual_pct', 6),
      aboveUsualPct: n(t, 'above_usual_pct', 4),
      baselineTests: n(t, 'baseline_tests', 3).round(),
    );
  }

  final double takeoffG, flightBelowG, landingAboveG, landingPeakG, minFlightS, maxFlightS, quietS, quietStdG;
  final int jumps;
  final double maxSeconds;
  final double belowUsualPct, aboveUsualPct;
  final int baselineTests;
}

class Jump {
  const Jump(this.takeoffS, this.landingS, this.landingPeakG);

  final double takeoffS;
  final double landingS;
  final double landingPeakG;

  double get flightS => landingS - takeoffS;

  /// Flight-time method: h = g t² / 8.
  double get heightCm => _gravity * flightS * flightS / 8 * 100;
}

double _std(Iterable<double> v) {
  final l = v.toList();
  final m = l.reduce((a, b) => a + b) / l.length;
  return math.sqrt(l.map((x) => (x - m) * (x - m)).reduce((a, b) => a + b) / l.length);
}

/// Standing jumps in [t] (s) / [g] (total |acc| in g): quiet stance, a push-off peak, a low-g flight, a
/// landing spike, quiet again. Same steps as the Python version.
List<Jump> detectJumps(List<double> t, List<double> g, JumpConfig c) {
  final jumps = <Jump>[];
  final n = g.length;
  Iterable<double> window(double from, double to, {bool inclusiveEnd = false}) sync* {
    for (var x = 0; x < n; x++) {
      if (t[x] >= from && (inclusiveEnd ? t[x] <= to : t[x] < to)) yield g[x];
    }
  }

  var i = 0;
  while (i < n) {
    if (g[i] < c.takeoffG) {
      i++;
      continue;
    }
    while (i + 1 < n && g[i + 1] >= g[i]) {
      i++;
    }
    final push = i;
    final before = window(t[push] - c.quietS - 0.3, t[push] - 0.3).toList();
    final quiet = before.length >= 5 && _std(before) <= c.quietStdG;
    var j = push;
    while (j < n && g[j] >= c.flightBelowG && t[j] - t[push] < 0.3) {
      j++;
    }
    if (!quiet || j >= n || g[j] >= c.flightBelowG) {
      i = push + 1;
      continue;
    }
    var k = j;
    while (k < n && g[k] <= c.landingAboveG && t[k] - t[j] <= c.maxFlightS) {
      k++;
    }
    if (k >= n || g[k] <= c.landingAboveG) {
      i = push + 1;
      continue;
    }
    final flight = t[k] - t[j];
    final after = window(t[k], t[k] + 0.15, inclusiveEnd: true).toList();
    final peak = after.reduce(math.max);
    final settle = window(t[k] + 0.4, t[k] + 0.4 + c.quietS).toList();
    final settled = settle.length >= 5 && _std(settle) <= 2 * c.quietStdG;
    if (flight >= c.minFlightS && flight <= c.maxFlightS && peak >= c.landingPeakG && settled) {
      jumps.add(Jump(t[j], t[k], peak));
      i = k + 1;
    } else {
      i = push + 1;
    }
  }
  return jumps;
}

/// One completed readiness check.
class JumpTestResult {
  const JumpTestResult(this.at, this.heightsCm, {this.source = 'sensor'});

  final DateTime at;
  final List<double> heightsCm;

  /// Which motion stream measured it: our sensor or the phone (they aren't compared with each other).
  final String source;

  /// The test's score: the mean of the two best jumps (one bad jump doesn't spoil the day).
  double get scoreCm {
    final s = List<double>.of(heightsCm)..sort((a, b) => b.compareTo(a));
    final top = s.take(2).toList();
    return top.isEmpty ? 0 : top.reduce((a, b) => a + b) / top.length;
  }

  double get bestCm => heightsCm.isEmpty ? 0 : heightsCm.reduce(math.max);

  Map<String, dynamic> toJson() => {
    'at': at.toIso8601String(),
    'heights_cm': [for (final h in heightsCm) double.parse(h.toStringAsFixed(1))],
    'source': source,
  };

  static JumpTestResult? fromJson(Object? j) {
    if (j is! Map) return null;
    final at = DateTime.tryParse(j['at'] as String? ?? '');
    final h = j['heights_cm'];
    if (at == null || h is! List) return null;
    return JumpTestResult(at, [for (final x in h) (x as num).toDouble()], source: j['source'] as String? ?? 'sensor');
  }

  static String encodeAll(List<JumpTestResult> all) => jsonEncode([for (final r in all) r.toJson()]);

  static List<JumpTestResult> decodeAll(String? s) {
    if (s == null || s.isEmpty) return [];
    try {
      return [for (final j in jsonDecode(s) as List) ?fromJson(j)];
    } on FormatException {
      return [];
    }
  }
}

enum JumpReadiness { noBaseline, below, normal, above }

/// [latest] against the athlete's usual: the median score of the earlier tests from the same source.
class JumpVerdict {
  const JumpVerdict(this.state, this.pct, this.usualCm);

  final JumpReadiness state;

  /// Latest score as % of usual (null without a baseline).
  final double? pct;
  final double? usualCm;

  String get title => switch (state) {
    JumpReadiness.noBaseline => 'Baseline building',
    JumpReadiness.below => 'Below your usual',
    JumpReadiness.normal => 'Normal for you',
    JumpReadiness.above => 'Above your usual',
  };

  String get advice => switch (state) {
    JumpReadiness.noBaseline =>
      'Do the check a few mornings in a row: from the third, each one is compared with your usual.',
    JumpReadiness.below =>
      'You jumped ${(100 - pct!).round()}% lower than usual. Keep today lighter: technique, skills, or a shorter session.',
    JumpReadiness.normal => 'Train as planned.',
    JumpReadiness.above => 'You jumped ${(pct! - 100).round()}% higher than usual: a good day for quality work.',
  };
}

JumpVerdict jumpVerdict(JumpTestResult latest, List<JumpTestResult> earlier, JumpConfig c) {
  final scores = [
    for (final r in earlier)
      if (r.source == latest.source && r.at.isBefore(latest.at) && r.heightsCm.isNotEmpty) r.scoreCm,
  ]..sort();
  if (scores.length < c.baselineTests || latest.heightsCm.isEmpty) {
    return const JumpVerdict(JumpReadiness.noBaseline, null, null);
  }
  final m = scores.length ~/ 2;
  final usual = scores.length.isOdd ? scores[m] : (scores[m - 1] + scores[m]) / 2;
  if (usual <= 0) return const JumpVerdict(JumpReadiness.noBaseline, null, null);
  final pct = latest.scoreCm / usual * 100;
  final state = pct <= 100 - c.belowUsualPct
      ? JumpReadiness.below
      : pct >= 100 + c.aboveUsualPct
      ? JumpReadiness.above
      : JumpReadiness.normal;
  return JumpVerdict(state, pct, usual);
}

/// A check in progress: collects total-g samples, finds jumps as they happen, stops after the profile's
/// number of jumps or its time limit.
class JumpTestRun {
  JumpTestRun(this.cfg, this.source, this._startMs);

  final JumpConfig cfg;
  final String source;
  final int _startMs;
  final List<double> _t = [];
  final List<double> _g = [];
  List<Jump> jumps = const [];
  bool done = false;
  bool timedOut = false;
  JumpTestResult? result;
  double elapsedS = 0;

  void add(int liveMs, double g) {
    final t = (liveMs - _startMs) / 1000;
    if (t < 0) return;
    if (_t.isNotEmpty && t < _t.last) return; // keep time order
    _t.add(t);
    _g.add(g);
  }

  /// Re-checks for jumps; returns true when the check has just finished.
  bool update(int liveMs) {
    if (done) return false;
    elapsedS = (liveMs - _startMs) / 1000;
    // Only jumps that have settled (landing + 0.4 s + quiet) can be confirmed: run on what's in.
    jumps = detectJumps(_t, _g, cfg);
    if (jumps.length >= cfg.jumps || elapsedS >= cfg.maxSeconds) {
      done = true;
      timedOut = jumps.length < cfg.jumps;
      result = jumps.isEmpty
          ? null
          : JumpTestResult(DateTime.now(), [for (final j in jumps.take(cfg.jumps)) j.heightCm], source: source);
      return true;
    }
    return false;
  }
}
