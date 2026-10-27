import 'dart:async';

import 'package:flutter/services.dart';

import 'motion_source.dart';

/// Live accelerometer from our Apple Watch app (strapped to the ankle or shin), relayed by the
/// iPhone side (ios/Runner/AppDelegate.swift, WatchMotionStream). Batches arrive about every 0.5 s.
/// Each sample carries its age, so the recorder stamps it when it was measured, not when it arrived.
class WatchMotionSource implements MotionSource {
  WatchMotionSource({this.batches});

  static const channel = EventChannel('livetraining/watch_motion');

  /// Batches to use instead of the platform channel (tests).
  final Stream<dynamic>? batches;
  StreamSubscription<dynamic>? _sub;
  StreamController<Sample>? _controller;

  /// Where the watch says it is worn, from the latest batch (e.g. `ankle`).
  String? placement;

  @override
  String get id => 'apple_watch';

  @override
  Stream<Sample> start() {
    if (_controller != null) return _controller!.stream;
    final controller = StreamController<Sample>.broadcast();
    _controller = controller;
    _sub = (batches ?? channel.receiveBroadcastStream()).listen(
      (event) {
        final batch = parseWatchBatch(event);
        if (batch == null) return;
        placement = batch.placement ?? placement;
        batch.samples.forEach(controller.add);
      },
      // No watch app, or not on iOS: there is simply no watch motion.
      onError: (Object _) {},
    );
    return controller.stream;
  }

  @override
  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    await _controller?.close();
    _controller = null;
  }
}

class WatchBatch {
  const WatchBatch(this.placement, this.samples);
  final String? placement;
  final List<Sample> samples;
}

/// `{type: motion, placement, sent, t: [...], x: [...], y: [...], z: [...]}` from the watch:
/// t and sent in seconds on the watch's clock, x/y/z in m/s² including gravity. Null if malformed.
WatchBatch? parseWatchBatch(Object? event) {
  if (event is! Map || event['type'] != 'motion') return null;
  final sent = event['sent'];
  final t = event['t'], x = event['x'], y = event['y'], z = event['z'];
  if (sent is! num || t is! List || x is! List || y is! List || z is! List) return null;
  final n = [t.length, x.length, y.length, z.length].reduce((a, b) => a < b ? a : b);
  final samples = <Sample>[
    for (var i = 0; i < n; i++)
      if (t[i] is num && x[i] is num && y[i] is num && z[i] is num)
        Sample.vector(
          'apple_watch',
          'acc',
          (x[i] as num).toDouble(),
          (y[i] as num).toDouble(),
          (z[i] as num).toDouble(),
          ageMs: ((sent - (t[i] as num)) * 1000).round().clamp(0, 60000),
        ),
  ];
  return WatchBatch(event['placement'] as String?, samples);
}
