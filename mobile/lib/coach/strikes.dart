/// Live footstrikes and impact load from a leg-worn sensor. A streaming version of
/// analysis/ltlib/steps.py `detect_strikes` + `impact_load`: local maxima of total |acc| (in g)
/// above a minimum, with no stronger peak closer than the minimum interval (that drops the other
/// foot's landing). Pure Dart, unit-testable.
library;

import 'dart:math' as math;

class _Peak {
  _Peak(this.t, this.g);
  final double t;
  final double g;
  bool decided = false;
}

class StrikeDetector {
  StrikeDetector({required this.minPeakG, required this.minIntervalS, required this.weightExponent});

  final double minPeakG;
  final double minIntervalS;
  final double weightExponent;

  int strikes = 0;
  double impactLoad = 0;
  double impactLoadWeighted = 0;
  double? hardestG;

  double? _t1, _g1, _g2; // the previous two samples
  final List<_Peak> _recent = [];

  /// [tS] seconds, [g] total acceleration in g. Samples in time order.
  void add(double tS, double g) {
    final g1 = _g1, g2 = _g2, t1 = _t1;
    if (g1 != null && g2 != null && t1 != null && g1 > minPeakG && g1 >= g2 && g1 >= g) _recent.add(_Peak(t1, g1));
    _g2 = g1;
    _g1 = g;
    _t1 = tS;

    // A peak is decided once no new peak within the interval after it can still arrive.
    for (final p in _recent) {
      if (p.decided || tS - p.t < minIntervalS) continue;
      p.decided = true;
      final beaten = _recent.any(
        (q) => !identical(q, p) && (q.t - p.t).abs() < minIntervalS && (q.g > p.g || (q.g == p.g && q.t < p.t)),
      );
      if (!beaten) _count(p.g);
    }
    _recent.removeWhere((p) => p.decided && tS - p.t >= 2 * minIntervalS);
  }

  void _count(double g) {
    strikes++;
    impactLoad += g;
    impactLoadWeighted += math.pow(g, weightExponent).toDouble();
    hardestG = math.max(hardestG ?? g, g);
  }
}
