/// Small pure helpers behind the live UI: recent history for sparklines, running session stats.
library;

/// Fixed-length history; null marks "no reading" (e.g. HR strap not connected).
class RollingSeries {
  RollingSeries(this.capacity);

  final int capacity;
  final List<double?> _values = [];

  List<double?> get values => List.unmodifiable(_values);

  void add(double? v) {
    _values.add(v);
    if (_values.length > capacity) _values.removeAt(0);
  }

  void clear() => _values.clear();

  /// (min, max) of the non-null values, or null if there are none.
  (double, double)? get range {
    double? lo, hi;
    for (final v in _values) {
      if (v == null) continue;
      lo = lo == null || v < lo ? v : lo;
      hi = hi == null || v > hi ? v : hi;
    }
    return lo == null ? null : (lo, hi!);
  }
}

/// Running numbers shown while recording. Sport-agnostic: no thresholds.
class SessionStats {
  int _hrCount = 0;
  double _hrSum = 0;
  double? hrMax;

  /// Integral of the live motion magnitude, in (m/s²)·min, same unit as the analysis "motion load".
  double load = 0;

  double? get hrAvg => _hrCount == 0 ? null : _hrSum / _hrCount;

  void addHr(double bpm) {
    _hrCount++;
    _hrSum += bpm;
    hrMax = hrMax == null || bpm > hrMax! ? bpm : hrMax;
  }

  void addMotion(double magnitude, double dtSeconds) => load += magnitude * dtSeconds / 60.0;
}
