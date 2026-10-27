import 'package:flutter_test/flutter_test.dart';
import 'package:live_training/ble/heart_rate_parser.dart';

void main() {
  group('parseHeartRateMeasurement', () {
    test('uint8 HR, no extras', () {
      final m = parseHeartRateMeasurement([0x00, 72]);
      expect(m.bpm, 72);
      expect(m.rrIntervalsMs, isEmpty);
      expect(m.energyExpendedKj, isNull);
      expect(m.sensorContact, isNull);
    });

    test('uint16 little-endian HR', () {
      // 0x012C = 300
      expect(parseHeartRateMeasurement([0x01, 0x2C, 0x01]).bpm, 300);
      expect(parseHeartRateMeasurement([0x01, 0x48, 0x00]).bpm, 72);
    });

    test('RR intervals converted from 1/1024 s to ms', () {
      // flags: RR present (bit 4). RR 1024 -> 1000 ms, RR 0x0355 (853) -> 833.0078 ms
      final m = parseHeartRateMeasurement([0x10, 72, 0x00, 0x04, 0x55, 0x03]);
      expect(m.bpm, 72);
      expect(m.rrIntervalsMs.length, 2);
      expect(m.rrIntervalsMs[0], 1000.0);
      expect(m.rrIntervalsMs[1], closeTo(833.0078, 1e-4));
    });

    test('energy expended is skipped before RR intervals', () {
      // flags: energy (bit 3) + RR (bit 4); energy 0x0102 = 258 kJ; RR 512 -> 500 ms
      final m = parseHeartRateMeasurement([0x18, 150, 0x02, 0x01, 0x00, 0x02]);
      expect(m.bpm, 150);
      expect(m.energyExpendedKj, 258);
      expect(m.rrIntervalsMs, [500.0]);
    });

    test('uint16 HR + energy + RR all together', () {
      final m = parseHeartRateMeasurement([0x19, 0xB4, 0x00, 0x10, 0x00, 0x00, 0x03]);
      expect(m.bpm, 180);
      expect(m.energyExpendedKj, 16);
      expect(m.rrIntervalsMs, [750.0]);
    });

    test('sensor contact bits', () {
      expect(parseHeartRateMeasurement([0x06, 60]).sensorContact, isTrue); // supported + detected
      expect(parseHeartRateMeasurement([0x04, 60]).sensorContact, isFalse); // supported, not detected
      expect(parseHeartRateMeasurement([0x02, 60]).sensorContact, isNull); // not supported
    });

    test('RR flag with no RR bytes yields empty list', () {
      expect(parseHeartRateMeasurement([0x10, 80]).rrIntervalsMs, isEmpty);
    });

    test('trailing odd byte is ignored', () {
      expect(parseHeartRateMeasurement([0x10, 80, 0x00, 0x04, 0x01]).rrIntervalsMs, [1000.0]);
    });

    test('malformed packets throw', () {
      expect(() => parseHeartRateMeasurement([]), throwsA(isA<HeartRateParseException>()));
      expect(() => parseHeartRateMeasurement([0x00]), throwsA(isA<HeartRateParseException>()));
      expect(() => parseHeartRateMeasurement([0x01, 0x48]), throwsA(isA<HeartRateParseException>()));
      expect(() => parseHeartRateMeasurement([0x08, 72, 0x01]), throwsA(isA<HeartRateParseException>()));
    });
  });
}
