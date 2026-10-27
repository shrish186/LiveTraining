import 'dart:async';

import 'package:sensors_plus/sensors_plus.dart';

import 'motion_source.dart';

/// The phone's own accelerometer (including gravity) and gyroscope, at the fastest rate the OS allows.
/// A stand-in until a body-worn sensor is plugged in.
class PhoneMotionSource implements MotionSource {
  StreamController<Sample>? _controller;
  final List<StreamSubscription<dynamic>> _subs = [];

  @override
  String get id => 'phone';

  @override
  Stream<Sample> start() {
    if (_controller != null) return _controller!.stream;
    final controller = StreamController<Sample>.broadcast();
    _controller = controller;
    _subs
      ..add(accelerometerEventStream(samplingPeriod: SensorInterval.fastestInterval).listen(
        (e) => controller.add(Sample.vector(id, 'acc', e.x, e.y, e.z)),
        onError: controller.addError,
      ))
      ..add(gyroscopeEventStream(samplingPeriod: SensorInterval.fastestInterval).listen(
        (e) => controller.add(Sample.vector(id, 'gyro', e.x, e.y, e.z)),
        onError: controller.addError,
      ));
    return controller.stream;
  }

  @override
  Future<void> stop() async {
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    await _controller?.close();
    _controller = null;
  }
}
