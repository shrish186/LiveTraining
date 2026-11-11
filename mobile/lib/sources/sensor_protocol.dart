/// Our leg sensor's Bluetooth stream: packet parsing and clock mapping. Spec: docs/sensor-protocol.md.
/// Pure Dart, unit-tested; the Bluetooth plumbing is in sensor_link.dart.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../util/motion.dart';
import 'motion_source.dart';

const sensorServiceUuid = '4c540001-7d2a-4b6e-9f3c-5a1e2b3c4d5e';
const sensorStreamUuid = '4c540002-7d2a-4b6e-9f3c-5a1e2b3c4d5e';
const sensorControlUuid = '4c540003-7d2a-4b6e-9f3c-5a1e2b3c4d5e';
const sensorStatusUuid = '4c540004-7d2a-4b6e-9f3c-5a1e2b3c4d5e';

/// The `source` column value for our own sensor (the XIAO-based prototype and its successors).
const sensorSourceId = 'xiao';

const _gyroRadPerCount = 0.070 * math.pi / 180; // 70 mdps per count

class SensorPacket {
  const SensorPacket(this.seq, this.firstMs, this.periodUs, this.acc, this.gyro);

  final int seq;
  final int firstMs;
  final int periodUs;

  /// m/s², gravity included, one [x, y, z] per sample.
  final List<List<double>> acc;

  /// rad/s, or empty when the packet has no gyro.
  final List<List<double>> gyro;

  int get count => acc.length;
  double sampleMs(int i) => firstMs + i * periodUs / 1000;
  double get lastMs => sampleMs(count - 1);
}

/// Null for anything that is not a well-formed version-1 packet.
SensorPacket? parseSensorPacket(List<int> bytes) {
  if (bytes.length < 12 || bytes[0] != 1) return null;
  final data = ByteData.sublistView(Uint8List.fromList(bytes));
  final hasGyro = bytes[1] & 1 == 1;
  final n = bytes[10];
  final recordSize = hasGyro ? 12 : 6;
  if (n == 0 || bytes.length < 12 + n * recordSize) return null;
  final toMs2 = bytes[11] / 1000 * gravity;
  final acc = <List<double>>[], gyro = <List<double>>[];
  for (var i = 0; i < n; i++) {
    final o = 12 + i * recordSize;
    double v(int k) => data.getInt16(o + 2 * k, Endian.little).toDouble();
    acc.add([v(0) * toMs2, v(1) * toMs2, v(2) * toMs2]);
    if (hasGyro) gyro.add([v(3) * _gyroRadPerCount, v(4) * _gyroRadPerCount, v(5) * _gyroRadPerCount]);
  }
  return SensorPacket(
    data.getUint16(2, Endian.little),
    data.getUint32(4, Endian.little),
    data.getUint16(8, Endian.little),
    acc,
    gyro,
  );
}

/// Maps the sensor's clock onto the phone's. Radio delay only makes packets late, so the smallest
/// (receive time − sensor time) seen is the true offset; it may creep up slowly to follow drift.
class SensorClock {
  SensorClock({this.driftMsPerS = 0.1});

  /// How fast the offset may rise when no fast packet confirms it (covers ±100 ppm crystals).
  final double driftMsPerS;
  double? _offset;
  double _lastReceiveMs = 0;

  /// Call once per packet with the phone's clock at arrival; returns the offset in ms.
  double update(double packetLastSensorMs, double receiveMs) {
    final candidate = receiveMs - packetLastSensorMs;
    final previous = _offset;
    _offset = previous == null
        ? candidate
        : math.min(candidate, previous + driftMsPerS * (receiveMs - _lastReceiveMs) / 1000);
    _lastReceiveMs = receiveMs;
    return _offset!;
  }
}

/// Turns packets into [Sample]s whose age places each one at its own time, and counts lost packets.
class SensorDecoder {
  final SensorClock _clock = SensorClock();
  int? _lastSeq;
  int packets = 0;
  int lostPackets = 0;

  double get lostPct => packets + lostPackets == 0 ? 0 : lostPackets / (packets + lostPackets) * 100;

  /// [receiveMs]: any monotonic phone clock in ms at the moment the packet arrived.
  List<Sample> decode(List<int> bytes, double receiveMs) {
    final p = parseSensorPacket(bytes);
    if (p == null) return const [];
    final last = _lastSeq;
    if (last != null) lostPackets += ((p.seq - last - 1) & 0xFFFF) % 0x8000;
    _lastSeq = p.seq;
    packets++;
    final offset = _clock.update(p.lastMs, receiveMs);
    final out = <Sample>[];
    for (var i = 0; i < p.count; i++) {
      final age = math.max(0, (receiveMs - (p.sampleMs(i) + offset)).round());
      final a = p.acc[i];
      out.add(Sample.vector(sensorSourceId, 'acc', a[0], a[1], a[2], ageMs: age));
      if (p.gyro.isNotEmpty) {
        final g = p.gyro[i];
        out.add(Sample.vector(sensorSourceId, 'gyro', g[0], g[1], g[2], ageMs: age));
      }
    }
    return out;
  }
}
