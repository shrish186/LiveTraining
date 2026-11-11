/// Live repeated big actions at the end of a run-up (in cricket: deliveries). A streaming version of
/// analysis/ltlib/actions.py `detect_actions` + `action_drift`, fed with the footstrikes of
/// [StrikeDetector]. Every number and the action's name come from the profile's `actions` block.
/// Pure Dart, unit-testable.
///
/// One difference from the Python: candidates closer than `min_gap_s` are resolved as they arrive
/// (the harder one replaces the pending one). Python picks the hardest of the whole session first.
/// They only differ for a chain of three or more candidates each within `min_gap_s` of the next.
library;

class ActionConfig {
  const ActionConfig({
    required this.label,
    required this.labelPlural,
    required this.minPeakG,
    required this.minRatio,
    required this.runupWindowS,
    required this.minRunupStrikes,
    required this.minGapS,
    required this.maxStrideS,
    required this.compare,
  });

  final String label;
  final String labelPlural;
  final double minPeakG;
  final double minRatio;
  final double runupWindowS;
  final int minRunupStrikes;
  final double minGapS;
  final double maxStrideS;
  final int compare;
}

class LiveAction {
  LiveAction(this.tS, this.peakG, this.runupStrikes, this.runupPeakG, this.runupStrideMs);

  int number = 0;
  final double tS;
  final double peakG;
  final int runupStrikes;
  final double runupPeakG;
  final double? runupStrideMs;
}

double _median(List<double> v) {
  final s = List<double>.of(v)..sort();
  final m = s.length ~/ 2;
  return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
}

double _mean(Iterable<double> v) => v.reduce((a, b) => a + b) / v.length;

class ActionDetector {
  ActionDetector(this.cfg);

  final ActionConfig cfg;
  final List<LiveAction> actions = [];
  final List<(double, double)> _strikes = []; // (t, g) within the run-up window
  LiveAction? _pending;

  /// A decided footstrike, in time order.
  void addStrike(double tS, double g) {
    final before = _strikes.where((s) => s.$1 >= tS - cfg.runupWindowS && s.$1 < tS).toList();
    _strikes
      ..add((tS, g))
      ..removeWhere((s) => s.$1 < tS - cfg.runupWindowS);
    if (g < cfg.minPeakG || before.length < cfg.minRunupStrikes) return;
    final runupPeak = _median([for (final s in before) s.$2]);
    if (g < cfg.minRatio * runupPeak) return;
    final gaps = <double>[
      for (var i = 1; i < before.length; i++)
        if (before[i].$1 - before[i - 1].$1 <= cfg.maxStrideS) before[i].$1 - before[i - 1].$1,
    ];
    final a = LiveAction(tS, g, before.length, runupPeak, gaps.isEmpty ? null : _median(gaps) * 1000);
    final p = _pending;
    if (p != null && tS - p.tS < cfg.minGapS) {
      if (g > p.peakG) _pending = a;
      return;
    }
    _confirm();
    _pending = a;
  }

  /// Confirms the pending action once nothing within `min_gap_s` can replace it. Returns new actions.
  List<LiveAction> tick(double nowS) {
    final p = _pending;
    if (p == null || nowS - p.tS < cfg.minGapS) return const [];
    return [_confirm()!];
  }

  /// Confirms what is pending, e.g. at the end of a session.
  List<LiveAction> finish() => _pending == null ? const [] : [_confirm()!];

  LiveAction? _confirm() {
    final p = _pending;
    if (p == null) return null;
    _pending = null;
    p.number = actions.length + 1;
    actions.add(p);
    return p;
  }

  /// Landing spike of the last `compare` actions vs the first `compare`, in % (null until 2 × compare).
  double? get peakDriftPct {
    final n = cfg.compare;
    if (n < 1 || actions.length < 2 * n) return null;
    final first = _mean(actions.take(n).map((a) => a.peakG));
    final last = _mean(actions.skip(actions.length - n).map((a) => a.peakG));
    return (last - first) / first * 100;
  }
}
