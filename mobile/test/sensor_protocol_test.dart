import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_training/sources/sensor_protocol.dart';

/// Builds a version-1 stream packet as the firmware would (docs/sensor-protocol.md).
List<int> packet({
  required int seq,
  required int firstMs,
  int periodUs = 10000,
  int scaleMg = 1,
  required List<List<int>> acc,
  List<List<int>>? gyro,
}) {
  final record = gyro == null ? 6 : 12;
  final b = ByteData(12 + acc.length * record)
    ..setUint8(0, 1)
    ..setUint8(1, gyro == null ? 0 : 1)
    ..setUint16(2, seq, Endian.little)
    ..setUint32(4, firstMs, Endian.little)
    ..setUint16(8, periodUs, Endian.little)
    ..setUint8(10, acc.length)
    ..setUint8(11, scaleMg);
  for (var i = 0; i < acc.length; i++) {
    for (var k = 0; k < 3; k++) {
      b.setInt16(12 + i * record + 2 * k, acc[i][k], Endian.little);
      if (gyro != null) b.setInt16(12 + i * record + 6 + 2 * k, gyro[i][k], Endian.little);
    }
  }
  return b.buffer.asUint8List();
}

void main() {
  test('parses acceleration in m/s² and gyro in rad/s', () {
    final p = parseSensorPacket(
      packet(
        seq: 7,
        firstMs: 123456,
        acc: [
          [0, 1000, 0],
          [-2000, 0, 500],
        ],
        gyro: [
          [0, 0, 0],
          [1000, 0, 0],
        ],
      ),
    )!;
    expect(p.seq, 7);
    expect(p.count, 2);
    expect(p.acc[0][1], closeTo(9.81, 1e-9)); // 1000 mg = 1 g
    expect(p.acc[1][0], closeTo(-19.62, 1e-9));
    expect(p.gyro[1][0], closeTo(70 * math.pi / 180, 1e-9)); // 1000 counts × 70 mdps
    expect(p.sampleMs(1), 123466);
  });

  test('high-g scale: 10 mg per count reaches 300 g', () {
    final p = parseSensorPacket(
      packet(
        seq: 0,
        firstMs: 0,
        scaleMg: 10,
        acc: [
          [30000, 0, 0],
        ],
      ),
    )!;
    expect(p.acc[0][0] / 9.81, closeTo(300, 1e-6));
  });

  test('parses packets built by the firmware code itself (hardware/firmware/test_packet.cpp)', () {
    List<int> bytes(String hex) => [
      for (var i = 0; i < hex.length; i += 2) int.parse(hex.substring(i, i + 2), radix: 16),
    ];
    final lines = File('test/fixtures/sensor_packet.hex').readAsLinesSync();

    final a = parseSensorPacket(bytes(lines[0]))!;
    expect(a.seq, 513);
    expect(a.firstMs, 123456789);
    expect(a.periodUs, 9615);
    expect(a.count, 3);
    expect(a.acc[0][1], closeTo(9.81, 1e-9));
    expect(a.acc[1][0] / 9.81, closeTo(-2.5, 1e-9));
    expect(a.acc[1][1] / 9.81, closeTo(16, 1e-9));
    expect(a.gyro[2][0], closeTo(70 * math.pi / 180, 1e-9));
    expect(a.gyro[2][2], closeTo(-70 * math.pi / 180, 1e-9));

    final b = parseSensorPacket(bytes(lines[1]))!;
    expect(b.seq, 65535);
    expect(b.firstMs, 4000000000);
    expect(b.gyro, isEmpty);
    expect(b.acc[0][0] / 9.81, closeTo(250, 1e-6), reason: 'high-g scale');
    expect(b.acc[0][1] / 9.81, closeTo(-1, 1e-6));

    expect(lines[2], '19 38 0 1', reason: 'samples per notification, as in docs/sensor-protocol.md');
  });

  test('rejects malformed packets', () {
    expect(parseSensorPacket([]), isNull);
    expect(parseSensorPacket([2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0]), isNull, reason: 'version');
    final short = packet(
      seq: 0,
      firstMs: 0,
      acc: [
        [1, 2, 3],
        [4, 5, 6],
      ],
    );
    expect(parseSensorPacket(short.sublist(0, short.length - 2)), isNull);
  });

  test('decoder: each sample gets its own age; radio delay does not shift time', () {
    final d = SensorDecoder();
    // 10 samples per packet at 100 Hz; sensor clock starts at 50 000 ms; phone clock offset +1000 ms.
    // Packets arrive 5 ms after their last sample, except packet 2, which is 80 ms late.
    final ages = <List<int>>[];
    for (var k = 0; k < 4; k++) {
      final first = 50000 + k * 100;
      final delay = k == 2 ? 80 : 5;
      final receive = first + 90 + 1000 + delay.toDouble();
      final samples = d.decode(packet(seq: k, firstMs: first, acc: List.filled(10, [0, 1000, 0])), receive);
      ages.add(samples.map((s) => s.ageMs).toList());
    }
    expect(ages[0], [90, 80, 70, 60, 50, 40, 30, 20, 10, 0], reason: 'first packet defines the offset');
    expect(ages[2].last, 75, reason: 'a late packet shows up as age, not as a time shift');
    expect(ages[3].last, 0);
    expect(d.lostPackets, 0);
  });

  test('decoder counts lost packets, across sequence wrap too', () {
    final d = SensorDecoder();
    for (final seq in [65534, 65535, 0, 3]) {
      d.decode(
        packet(
          seq: seq,
          firstMs: 0,
          acc: [
            [0, 0, 0],
          ],
        ),
        0,
      );
    }
    expect(d.packets, 4);
    expect(d.lostPackets, 2);
    expect(d.lostPct, closeTo(33.3, 0.1));
  });

  test('clock follows slow drift', () {
    final c = SensorClock();
    var offset = 0.0;
    for (var s = 0; s <= 600; s++) {
      // Sensor crystal 50 ppm slow: the true offset grows 0.05 ms per second.
      offset = c.update(s * 1000.0, s * 1000.0 + 500 + s * 0.05 + (s % 7 == 0 ? 0 : 12));
    }
    expect(offset, closeTo(500 + 600 * 0.05, 3));
  });
}
