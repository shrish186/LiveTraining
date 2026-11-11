/// Data quality of one accelerometer stream. Twin of analysis/ltlib/quality.py `stream_quality`:
/// lost samples, dropouts, clipping, gravity (calibration) error, strap movement, and a grade.
/// Thresholds come from the sport profile's `quality` block. Pure Dart.
library;

import 'dart:math' as math;

import '../util/motion.dart';

class QualityConfig {
  const QualityConfig({
    required this.gapMs,
    required this.maxLostPct,
    required this.clipMinSamples,
    required this.stillStdG,
    required this.gravityTolerancePct,
    required this.maxTiltChangeDeg,
  });

  factory QualityConfig.fromProfile(Map<String, dynamic> profile) {
    final q = profile['quality'] as Map<String, dynamic>;
    double n(String key) => (q[key] as num).toDouble();
    return QualityConfig(
      gapMs: n('gap_ms'),
      maxLostPct: n('max_lost_pct'),
      clipMinSamples: (q['clip_min_samples'] as num).toInt(),
      stillStdG: n('still_std_g'),
      gravityTolerancePct: n('gravity_tolerance_pct'),
      maxTiltChangeDeg: n('max_tilt_change_deg'),
    );
  }

  final double gapMs;
  final double maxLostPct;
  final int clipMinSamples;
  final double stillStdG;
  final double gravityTolerancePct;
  final double maxTiltChangeDeg;
}

enum QualityGrade { good, fair, poor }

class StreamQuality {
  StreamQuality({
    required this.samples,
    required this.durationS,
    required this.rateHz,
    required this.lostPct,
    required this.gaps,
    required this.longestGapS,
    required this.clippedPct,
    this.clipLevelG,
    this.gravityErrorPct,
    this.tiltChangeDeg,
  });

  final int samples;
  final double durationS;
  final double rateHz;
  final double lostPct;
  final int gaps;
  final double longestGapS;
  final double clippedPct;
  final double? clipLevelG;
  final double? gravityErrorPct;
  final double? tiltChangeDeg;
  int score = 100;
  QualityGrade grade = QualityGrade.good;
  final List<String> issues = [];
}

double _median(List<double> values) {
  final v = List<double>.of(values)..sort();
  final mid = v.length ~/ 2;
  return v.length.isOdd ? v[mid] : (v[mid - 1] + v[mid]) / 2;
}

/// [t] seconds in time order; [x], [y], [z] in m/s² including gravity. Null if there is too little data.
StreamQuality? streamQuality(List<double> t, List<double> x, List<double> y, List<double> z, QualityConfig cfg) {
  final n = t.length;
  if (n < 20) return null;
  final duration = t.last - t.first;
  if (duration <= 0) return null;

  // Rate and loss, against the typical whole second.
  final seconds = math.max(duration.floor(), 1);
  final perSecond = List<double>.filled(seconds, 0);
  for (final ti in t) {
    final s = (ti - t.first).floor();
    if (s < seconds) perSecond[s]++;
  }
  final rate = _median(perSecond);
  final expected = rate * duration;
  final lostPct = expected > 0 ? math.max(0.0, (1 - n / expected) * 100) : 0.0;

  // A dropout is judged against the stream's own rate: at 20 Hz a 50 ms interval is normal.
  final gapS = math.max(cfg.gapMs / 1000, rate > 0 ? 3 / rate : 0.0);
  var gaps = 0;
  var longestGap = 0.0;
  for (var i = 1; i < n; i++) {
    final dt = t[i] - t[i - 1];
    if (dt > gapS) gaps++;
    longestGap = math.max(longestGap, dt);
  }

  // Clipping: a sensor at its limit repeats the same top value; real peaks are single samples.
  var peak = 0.0;
  for (var i = 0; i < n; i++) {
    peak = math.max(peak, math.max(x[i].abs(), math.max(y[i].abs(), z[i].abs())));
  }
  var atLimit = 0;
  for (var i = 0; i < n; i++) {
    if (math.max(x[i].abs(), math.max(y[i].abs(), z[i].abs())) >= 0.995 * peak) atLimit++;
  }
  final clipping = atLimit >= cfg.clipMinSamples && peak > 1.5 * gravity;

  // Rest windows (1 s): mean vector where |acc| barely varies.
  final rests = <List<double>>[];
  var a = 0;
  for (var edge = t.first + 1.0; edge <= t.last; edge += 1.0) {
    var b = a;
    while (b < n && t[b] < edge) {
      b++;
    }
    if (b - a >= 5) {
      var sum = 0.0, sumSq = 0.0, sx = 0.0, sy = 0.0, sz = 0.0;
      for (var i = a; i < b; i++) {
        final m = math.sqrt(x[i] * x[i] + y[i] * y[i] + z[i] * z[i]) / gravity;
        sum += m;
        sumSq += m * m;
        sx += x[i];
        sy += y[i];
        sz += z[i];
      }
      final k = b - a;
      final std = math.sqrt(math.max(0.0, sumSq / k - (sum / k) * (sum / k)));
      if (std <= cfg.stillStdG) rests.add([sx / k, sy / k, sz / k]);
    }
    a = b;
  }
  double norm(List<double> v) => math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
  double? gravityError, tilt;
  if (rests.isNotEmpty) {
    gravityError = (_median(rests.map(norm).toList()) / gravity - 1).abs() * 100;
    if (rests.length >= 2) {
      final f = rests.first, l = rests.last;
      final cos = (f[0] * l[0] + f[1] * l[1] + f[2] * l[2]) / (norm(f) * norm(l));
      tilt = math.acos(cos.clamp(-1.0, 1.0)) * 180 / math.pi;
    }
  }

  final q = StreamQuality(
    samples: n,
    durationS: duration,
    rateHz: rate,
    lostPct: lostPct,
    gaps: gaps,
    longestGapS: longestGap,
    clippedPct: clipping ? atLimit / n * 100 : 0,
    clipLevelG: clipping ? peak / gravity : null,
    gravityErrorPct: gravityError,
    tiltChangeDeg: tilt,
  );

  var penalty = 0.0;
  if (q.lostPct > cfg.maxLostPct) {
    penalty += math.min(40, q.lostPct * 4);
    q.issues.add('${q.lostPct.toStringAsFixed(1)}% of samples missing');
  }
  if (q.gaps > 0) {
    penalty += math.min(30, 5 * q.gaps + 10 * math.max(0.0, q.longestGapS - 1));
    q.issues.add('${q.gaps} dropout${q.gaps == 1 ? '' : 's'}, longest ${q.longestGapS.toStringAsFixed(1)} s');
  }
  if (q.clipLevelG != null) {
    penalty += math.min(30, 10 + q.clippedPct * 20);
    q.issues.add('Sensor hit its limit (${q.clipLevelG!.round()} g): impact peaks read low');
  }
  if (gravityError != null && gravityError > cfg.gravityTolerancePct) {
    penalty += 15;
    q.issues.add('Reads gravity ${gravityError.round()}% off: needs calibration');
  }
  if (tilt != null && tilt > cfg.maxTiltChangeDeg) {
    penalty += 15;
    q.issues.add('Sensor angle changed ${tilt.round()}° from start to end: the strap may have moved');
  }
  q.score = math.max(0.0, 100 - penalty).round();
  q.grade = q.score >= 85
      ? QualityGrade.good
      : q.score >= 60
      ? QualityGrade.fair
      : QualityGrade.poor;
  return q;
}
