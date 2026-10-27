/// Live calls during a session. A streaming port of analysis/ltlib/core.py: same smoothing
/// (100 ms bins + 1 s mean), same effort rule, same HR-recovery and fatigue rule, fed sample by
/// sample instead of on the whole file. Every number comes from [CoachConfig] (a sport profile).
/// Pure Dart, no Flutter imports, so it is unit-testable.
library;

import 'dart:math' as math;

import '../util/motion.dart';
import 'profiles.dart';

enum CallType { readiness, warmedUp, effort, fatigue }

class CoachCall {
  const CoachCall(this.type, this.tMs, this.title, this.detail);

  final CallType type;
  final int tMs;
  final String title;
  final String detail;

  /// Written into the session CSV as an event, so calls show up in the analysis plot.
  String get eventLabel => switch (type) {
    CallType.readiness => 'call_readiness',
    CallType.warmedUp => 'call_warmed_up',
    CallType.effort => 'call_effort',
    CallType.fatigue => 'call_fatigue',
  };

  /// Calls worth a strong buzz (the athlete may not be looking at the screen).
  bool get important => type != CallType.effort;
}

class LiveEffort {
  LiveEffort(this.number, this.startS, this.endS, this.peak);

  final int number;
  final double startS;
  final double endS;
  final double peak;
  double? hrRecoveryBpm;
  double? peakDropPct;
  bool resolved = false; // HR recovery known (or known to be unavailable)
  bool assessed = false;
  bool fatigue = false;

  double get durationS => endS - startS;
}

class LiveCoach {
  LiveCoach(this.cfg, {this.restingHr, this.recoveryScore})
    : _windowBins = math.max(1, (cfg.smoothingWindowS * gridHz).round());

  static const gridHz = 10; // same grid as analysis/ltlib/core.py
  static const _hrMaxGapS = 5.0;

  final CoachConfig cfg;

  /// From WHOOP. Without it, warm-up is measured against the lowest HR of the first minute.
  final double? restingHr;
  final double? recoveryScore;

  // Motion smoothing
  final int _windowBins;
  final List<double> _window = [];
  int? _bin;
  double _binSum = 0;
  int _binCount = 0;
  double smoothed = 0;

  // Effort detection
  double? _runStartS;
  double _lastAboveS = 0;
  double _runPeak = 0;
  final List<LiveEffort> efforts = [];

  // Heart rate
  final List<double> _hrT = [];
  final List<double> _hrV = [];
  double? _firstMinuteMin;

  // Warm-up
  bool warmedUp = false;
  double? _aboveSinceS;

  final List<CoachCall> _pending = [];
  double _nowS = 0;

  bool get inEffort => _runStartS != null;

  double? get latestHr => _hrV.isEmpty || _nowS - _hrT.last > _hrMaxGapS ? null : _hrV.last;

  /// HR that counts as warmed up, or null until a resting reference is known.
  double? get warmupTargetHr {
    final rest = restingHr ?? (_nowS >= 60 ? _firstMinuteMin : null);
    return rest == null ? null : rest + cfg.warmupHrAboveRest;
  }

  /// Calls to show when the session starts.
  List<CoachCall> start() {
    final score = recoveryScore;
    if (score == null) return const [];
    final pct = score.round();
    final call = score >= cfg.readinessHighFrom
        ? CoachCall(CallType.readiness, 0, 'High readiness · $pct%', 'Recovered well. A good day to push the hard sets.')
        : score < cfg.readinessLowBelow
        ? CoachCall(CallType.readiness, 0, 'Low readiness · $pct%', 'Recovery is low. Keep today\'s load lighter.')
        : CoachCall(
            CallType.readiness,
            0,
            'Moderate readiness · $pct%',
            'Train as planned and watch how the efforts feel.',
          );
    return [call];
  }

  void addAcc(int tMs, double x, double y, double z) {
    final bin = tMs ~/ (1000 ~/ gridHz);
    if (_bin != null && bin != _bin) _closeBin();
    _bin = bin;
    _binSum += dynamicMagnitude(x, y, z);
    _binCount++;
  }

  void addHr(int tMs, double bpm) {
    final t = tMs / 1000;
    _hrT.add(t);
    _hrV.add(bpm);
    if (t <= 60) _firstMinuteMin = _firstMinuteMin == null ? bpm : math.min(_firstMinuteMin!, bpm);
  }

  /// Advances the clock; returns any new calls. Call it a few times per second.
  List<CoachCall> tick(int tMs) {
    _nowS = tMs / 1000;
    _checkWarmup();
    _resolveRecoveries();
    _assessFatigue();
    final out = List<CoachCall>.of(_pending);
    _pending.clear();
    return out;
  }

  // ---- motion --------------------------------------------------------------

  void _closeBin() {
    final mean = _binSum / _binCount;
    _binSum = 0;
    _binCount = 0;
    _window.add(mean);
    if (_window.length > _windowBins) _window.removeAt(0);
    smoothed = _window.reduce((a, b) => a + b) / _window.length;
    _onSmoothed(_bin! / gridHz, smoothed);
  }

  void _onSmoothed(double tS, double value) {
    if (value > cfg.effortThreshold) {
      _runStartS ??= tS;
      if (_runStartS == tS) _runPeak = value;
      _lastAboveS = tS;
      _runPeak = math.max(_runPeak, value);
    } else if (_runStartS != null && tS - _lastAboveS > cfg.mergeGapS) {
      final start = _runStartS!;
      final end = _lastAboveS + 1 / gridHz;
      _runStartS = null;
      if (end - start >= cfg.minEffortS) {
        final e = LiveEffort(efforts.length + 1, start, end, _runPeak);
        efforts.add(e);
        _pending.add(
          CoachCall(
            CallType.effort,
            (end * 1000).round(),
            'Effort ${e.number} · ${e.durationS.round()} s',
            'Peak ${e.peak.toStringAsFixed(1)} m/s²',
          ),
        );
      }
    }
  }

  // ---- heart rate ------------------------------------------------------------

  /// HR interpolated at t, or null if no sample within 5 s (as hr_at in core.py).
  double? _hrAt(double t) {
    if (_hrT.isEmpty) return null;
    var nearest = double.infinity;
    for (final ht in _hrT) {
      nearest = math.min(nearest, (ht - t).abs());
    }
    if (nearest > _hrMaxGapS) return null;
    if (t <= _hrT.first) return _hrV.first;
    if (t >= _hrT.last) return _hrV.last;
    for (var i = 1; i < _hrT.length; i++) {
      if (_hrT[i] >= t) {
        final f = (t - _hrT[i - 1]) / (_hrT[i] - _hrT[i - 1]);
        return _hrV[i - 1] + f * (_hrV[i] - _hrV[i - 1]);
      }
    }
    return _hrV.last;
  }

  void _checkWarmup() {
    if (warmedUp) return;
    final target = warmupTargetHr;
    final hr = latestHr;
    if (target == null || hr == null || hr < target) {
      _aboveSinceS = null;
      return;
    }
    _aboveSinceS ??= _nowS;
    if (_nowS >= cfg.warmupMinS && _nowS - _aboveSinceS! >= cfg.warmupSustainS) {
      warmedUp = true;
      final rest = (target - cfg.warmupHrAboveRest).round();
      _pending.add(
        CoachCall(
          CallType.warmedUp,
          (_nowS * 1000).round(),
          'Warmed up, go',
          'Heart rate ${hr.round()} has held ${cfg.warmupHrAboveRest.round()}+ above your resting $rest.',
        ),
      );
    }
  }

  void _resolveRecoveries() {
    final window = cfg.hrRecoveryWindowS;
    for (var i = 0; i < efforts.length; i++) {
      final e = efforts[i];
      if (e.resolved) continue;
      final later = e.endS + window;
      final nextStart = i + 1 < efforts.length ? efforts[i + 1].startS : _runStartS;
      if (nextStart != null && nextStart < later) {
        e.resolved = true; // next effort inside the recovery window: no HR recovery (as core.py)
        continue;
      }
      if (_nowS < later + 2) continue; // wait for HR samples just after the window
      final atEnd = _hrAt(e.endS);
      final after = _hrAt(later);
      e.hrRecoveryBpm = atEnd == null || after == null ? null : atEnd - after;
      e.resolved = true;
    }
  }

  void _assessFatigue() {
    final baseline = efforts.where((e) => e.startS < cfg.baselineWindowS).toList();
    // Judge later efforts only once the early ones are fully known.
    if (baseline.isEmpty || _nowS < cfg.baselineWindowS || baseline.any((e) => !e.resolved)) return;
    final basePeak = baseline.map((e) => e.peak).reduce((a, b) => a + b) / baseline.length;
    final baseHrrValues = baseline.map((e) => e.hrRecoveryBpm).whereType<double>().toList();
    final baseHrr = baseHrrValues.isEmpty ? null : baseHrrValues.reduce((a, b) => a + b) / baseHrrValues.length;

    for (final e in efforts) {
      if (e.startS < cfg.baselineWindowS || e.assessed || !e.resolved) continue;
      e.assessed = true;
      e.peakDropPct = (basePeak - e.peak) / basePeak * 100;
      final slower = baseHrr != null && e.hrRecoveryBpm != null && e.hrRecoveryBpm! < baseHrr;
      e.fatigue = e.peakDropPct! >= cfg.peakDropPct && slower;
      if (e.fatigue) {
        _pending.add(
          CoachCall(
            CallType.fatigue,
            (_nowS * 1000).round(),
            'Fatigue building',
            'Effort ${e.number} was ${e.peakDropPct!.round()}% weaker than your early efforts and heart rate '
                'recovered slower (${e.hrRecoveryBpm!.round()} vs ${baseHrr!.round()} bpm). '
                'Consider cutting the last set.',
          ),
        );
      }
    }
  }
}
