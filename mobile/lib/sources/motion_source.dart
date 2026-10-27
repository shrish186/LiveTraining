/// One reading from any source. Time is NOT part of a sample: the SessionRecorder stamps every
/// sample on arrival with one shared monotonic Stopwatch (see docs/session-format.md). A source that
/// delivers in batches (e.g. the watch) sets [ageMs], how long ago the reading was taken, and the
/// recorder stamps it that much earlier.
class Sample {
  const Sample.vector(this.source, this.kind, double this.x, double this.y, double this.z, {this.ageMs = 0})
    : value = null,
      label = null;

  const Sample.scalar(this.source, this.kind, double this.value)
    : x = null,
      y = null,
      z = null,
      label = null,
      ageMs = 0;

  const Sample.event(this.source, String this.label)
    : kind = 'event',
      x = null,
      y = null,
      z = null,
      value = null,
      ageMs = 0;

  /// `phone`, `whoop_hr`, `apple_watch`, `movesense`, `xiao`, `polar`
  final String source;

  /// `acc`, `gyro`, `hr`, `rr`, `event`
  final String kind;
  final double? x, y, z;
  final double? value;
  final String? label;

  /// Milliseconds between taking the reading and handing it over (0 for live sensors).
  final int ageMs;
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
