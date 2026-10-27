import 'dart:math' as math;

const gravity = 9.81;

/// | |acc| - g |, same definition as analysis/ltlib/core.py.
double dynamicMagnitude(double x, double y, double z) => (math.sqrt(x * x + y * y + z * z) - gravity).abs();

/// Exponential moving average with a time constant, for the live motion readout.
class LiveMagnitude {
  LiveMagnitude({this.timeConstantMs = 500});

  final double timeConstantMs;
  double value = 0;
  int? _lastMs;

  double add(double x, double y, double z, int tMs) {
    final m = dynamicMagnitude(x, y, z);
    final last = _lastMs;
    _lastMs = tMs;
    if (last == null) return value = m;
    final dt = (tMs - last).clamp(0, 1000).toDouble();
    final alpha = dt / (timeConstantMs + dt);
    return value += alpha * (m - value);
  }
}
