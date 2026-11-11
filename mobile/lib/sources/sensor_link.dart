import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import 'motion_source.dart';
import 'sensor_protocol.dart';

/// A leg sensor seen in a scan.
class FoundSensor {
  const FoundSensor(this.id, this.name);
  final String id;
  final String name;
}

/// Scans for our leg sensors (devices advertising the sensor service).
class SensorScanner {
  SensorScanner({FlutterReactiveBle? ble}) : _bleOverride = ble;

  final FlutterReactiveBle? _bleOverride;
  late final FlutterReactiveBle ble = _bleOverride ?? FlutterReactiveBle();

  Future<List<FoundSensor>> scan({Duration duration = const Duration(seconds: 5)}) async {
    final found = <String, FoundSensor>{};
    final sub = ble
        .scanForDevices(
          withServices: [Uuid.parse(sensorServiceUuid)],
          scanMode: ScanMode.lowLatency,
          requireLocationServicesEnabled: false,
        )
        .listen((d) => found[d.id] = FoundSensor(d.id, d.name.isEmpty ? 'Sensor' : d.name), onError: (Object _) {});
    await Future<void>.delayed(duration);
    await sub.cancel();
    return found.values.toList()..sort((a, b) => a.name.compareTo(b.name));
  }
}

enum SensorState { connecting, live, lost }

/// One connected leg sensor: keeps the connection up and turns its packets into [Sample]s.
class SensorLink extends ChangeNotifier implements MotionSource {
  SensorLink(this.sensor, {this.ble, Stream<List<int>>? packets}) : _testPackets = packets;

  final FoundSensor sensor;
  final FlutterReactiveBle? ble;

  /// Packets to use instead of Bluetooth (tests).
  final Stream<List<int>>? _testPackets;

  final SensorDecoder decoder = SensorDecoder();
  final Stopwatch _clock = Stopwatch()..start();
  SensorState state = SensorState.connecting;
  StreamController<Sample>? _controller;
  StreamSubscription<ConnectionStateUpdate>? _connSub;
  StreamSubscription<List<int>>? _packetSub;
  Timer? _retry;
  bool _wanted = false;

  @override
  String get id => sensorSourceId;

  @override
  Stream<Sample> start() {
    if (_controller != null) return _controller!.stream;
    _controller = StreamController<Sample>.broadcast();
    _wanted = true;
    final test = _testPackets;
    test != null ? _listen(test) : _connect();
    return _controller!.stream;
  }

  void _set(SensorState s) {
    if (state == s) return;
    state = s;
    notifyListeners();
  }

  void _connect() {
    final ble = this.ble ?? FlutterReactiveBle();
    final service = Uuid.parse(sensorServiceUuid), stream = Uuid.parse(sensorStreamUuid);
    _connSub?.cancel();
    _connSub = ble
        .connectToDevice(
          id: sensor.id,
          servicesWithCharacteristicsToDiscover: {
            service: [stream],
          },
          connectionTimeout: const Duration(seconds: 15),
        )
        .listen((update) {
          if (update.connectionState == DeviceConnectionState.connected) {
            _listen(
              ble.subscribeToCharacteristic(
                QualifiedCharacteristic(serviceId: service, characteristicId: stream, deviceId: sensor.id),
              ),
            );
          } else if (update.connectionState == DeviceConnectionState.disconnected) {
            _dropped();
          }
        }, onError: (Object _) => _dropped());
  }

  void _listen(Stream<List<int>> packets) {
    _packetSub?.cancel();
    _packetSub = packets.listen((bytes) {
      final samples = decoder.decode(bytes, _clock.elapsedMicroseconds / 1000);
      if (samples.isEmpty) return;
      _set(SensorState.live);
      samples.forEach(_controller!.add);
    }, onError: (Object _) => _dropped());
  }

  /// Keeps retrying while the sensor is wanted: players walk out of range and come back.
  void _dropped() {
    _packetSub?.cancel();
    _packetSub = null;
    _set(SensorState.lost);
    _retry?.cancel();
    if (_wanted && _testPackets == null) _retry = Timer(const Duration(seconds: 2), _connect);
  }

  @override
  Future<void> stop() async {
    _wanted = false;
    _retry?.cancel();
    await _packetSub?.cancel();
    await _connSub?.cancel(); // cancelling the connection stream disconnects
    await _controller?.close();
    _controller = null;
  }
}
