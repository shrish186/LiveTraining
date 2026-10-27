import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import '../ble/heart_rate_parser.dart';
import 'motion_source.dart';

enum HrConnection { idle, scanning, connecting, connected, reconnecting, error }

/// WHOOP heart rate via WHOOP's built-in Heart Rate Broadcast: the STANDARD Bluetooth Heart Rate
/// service (0x180D), measurement characteristic 0x2A37. No private WHOOP protocol is used.
/// Turn it on in the WHOOP app (Device settings → Heart Rate Broadcast).
///
/// Works with any standard BLE heart-rate strap; WHOOP-named devices are preferred when several
/// are in range.
class WhoopHrSource extends ChangeNotifier {
  WhoopHrSource({FlutterReactiveBle? ble}) : _ble = ble ?? FlutterReactiveBle();

  static final heartRateService = Uuid.parse('180D');
  static final heartRateMeasurement = Uuid.parse('2A37');
  static const sourceId = 'whoop_hr';
  static const scanTimeout = Duration(seconds: 10);

  final FlutterReactiveBle _ble;
  final _samples = StreamController<Sample>.broadcast();

  HrConnection state = HrConnection.idle;
  String? deviceName;
  String? error;
  int? lastBpm;

  String? _deviceId;
  bool _wanted = false;
  StreamSubscription<DiscoveredDevice>? _scanSub;
  StreamSubscription<ConnectionStateUpdate>? _connSub;
  StreamSubscription<List<int>>? _notifySub;
  Timer? _retry;

  /// `hr` samples (bpm) and `rr` samples (ms).
  Stream<Sample> get samples => _samples.stream;

  void _set(HrConnection s, {String? err}) {
    state = s;
    error = err;
    notifyListeners();
  }

  /// For failures found before scanning starts, e.g. a denied permission.
  void reportError(String message) => _set(HrConnection.error, err: message);

  Future<void> connect() async {
    if (_wanted && state != HrConnection.error) return;
    _wanted = true;
    await _cancelAll();
    _set(HrConnection.scanning);

    final found = <DiscoveredDevice>[];
    final done = Completer<DiscoveredDevice?>();
    _scanSub = _ble.scanForDevices(
      withServices: [heartRateService],
      scanMode: ScanMode.lowLatency,
      requireLocationServicesEnabled: false,
    ).listen((d) {
      if (found.every((f) => f.id != d.id)) found.add(d);
      if (d.name.toLowerCase().contains('whoop') && !done.isCompleted) done.complete(d);
    }, onError: (Object e) {
      if (!done.isCompleted) done.completeError(e);
    });
    Timer(scanTimeout, () {
      if (!done.isCompleted) done.complete(found.isEmpty ? null : found.first);
    });

    DiscoveredDevice? device;
    try {
      device = await done.future;
    } catch (e) {
      await _scanSub?.cancel();
      _wanted = false;
      _set(HrConnection.error, err: 'Bluetooth scan failed: $e');
      return;
    }
    await _scanSub?.cancel();
    _scanSub = null;
    if (!_wanted) return;
    if (device == null) {
      _wanted = false;
      _set(HrConnection.error,
          err: 'No heart-rate broadcast found. In the WHOOP app, turn on Heart Rate Broadcast.');
      return;
    }
    _deviceId = device.id;
    deviceName = device.name.isEmpty ? 'Heart rate sensor' : device.name;
    _connectTo(device.id);
  }

  void _connectTo(String id) {
    _set(state == HrConnection.reconnecting ? HrConnection.reconnecting : HrConnection.connecting);
    _connSub = _ble.connectToDevice(
      id: id,
      servicesWithCharacteristicsToDiscover: {heartRateService: [heartRateMeasurement]},
      connectionTimeout: const Duration(seconds: 15),
    ).listen((update) {
      switch (update.connectionState) {
        case DeviceConnectionState.connected:
          _subscribe(id);
        case DeviceConnectionState.disconnected:
          _onDropped();
        case DeviceConnectionState.connecting:
        case DeviceConnectionState.disconnecting:
          break;
      }
    }, onError: (Object e) => _onDropped());
  }

  void _subscribe(String id) {
    _notifySub?.cancel();
    final characteristic =
        QualifiedCharacteristic(serviceId: heartRateService, characteristicId: heartRateMeasurement, deviceId: id);
    _notifySub = _ble.subscribeToCharacteristic(characteristic).listen((data) {
      try {
        final m = parseHeartRateMeasurement(data);
        lastBpm = m.bpm;
        _samples.add(Sample.scalar(sourceId, 'hr', m.bpm.toDouble()));
        for (final rr in m.rrIntervalsMs) {
          _samples.add(Sample.scalar(sourceId, 'rr', rr));
        }
        if (state != HrConnection.connected) _set(HrConnection.connected);
      } on HeartRateParseException {
        // Ignore a malformed packet; the next one arrives within ~1 s.
      }
    }, onError: (Object e) => _onDropped());
    _set(HrConnection.connected);
  }

  /// Unexpected drop: keep retrying the same device while the user wants a connection.
  void _onDropped() {
    _notifySub?.cancel();
    _notifySub = null;
    _connSub?.cancel();
    _connSub = null;
    lastBpm = null;
    if (!_wanted || _deviceId == null) {
      _set(HrConnection.idle);
      return;
    }
    _set(HrConnection.reconnecting);
    _retry?.cancel();
    _retry = Timer(const Duration(seconds: 2), () {
      if (_wanted && _deviceId != null) _connectTo(_deviceId!);
    });
  }

  Future<void> disconnect() async {
    _wanted = false;
    await _cancelAll();
    lastBpm = null;
    _set(HrConnection.idle);
  }

  Future<void> _cancelAll() async {
    _retry?.cancel();
    await _scanSub?.cancel();
    await _notifySub?.cancel();
    await _connSub?.cancel(); // cancelling the connection stream disconnects
    _scanSub = null;
    _notifySub = null;
    _connSub = null;
  }

  @override
  void dispose() {
    _cancelAll();
    _samples.close();
    super.dispose();
  }
}
