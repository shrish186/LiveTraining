/// One reading from any source. Time is NOT part of a sample: the SessionRecorder stamps every
/// sample on arrival with one shared monotonic Stopwatch (see docs/session-format.md).
class Sample {
  const Sample.vector(this.source, this.kind, double this.x, double this.y, double this.z)
      : value = null,
        label = null;

  const Sample.scalar(this.source, this.kind, double this.value)
      : x = null,
        y = null,
        z = null,
        label = null;

  const Sample.event(this.source, String this.label)
      : kind = 'event',
        x = null,
        y = null,
        z = null,
        value = null;

  /// `phone`, `whoop_hr`, `movesense`, `xiao`, `polar`
  final String source;

  /// `acc`, `gyro`, `hr`, `rr`, `event`
  final String kind;
  final double? x, y, z;
  final double? value;
  final String? label;
}

/// A body-worn (or stand-in) motion sensor. Add Movesense, XIAO, Polar, … by implementing this.
/// The recorder only ever sees [Sample]s, so it never changes when a source is added.
abstract class MotionSource {
  /// Matches the `source` column, e.g. `phone`.
  String get id;

  /// Starts the sensor and returns its samples (acc in m/s² including gravity, gyro in rad/s).
  Stream<Sample> start();

  Future<void> stop();
}
