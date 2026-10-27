/// Parser for the standard Bluetooth Heart Rate Measurement characteristic (0x2A37).
///
/// Layout (Bluetooth Heart Rate Service spec):
///   byte 0  flags
///     bit 0    HR value format: 0 = uint8, 1 = uint16 little-endian
///     bit 1-2  sensor contact status (bit 2 = supported, bit 1 = detected)
///     bit 3    energy expended present (uint16, kJ)
///     bit 4    RR intervals present (one or more uint16, units of 1/1024 s)
///   then HR value, optional energy expended, optional RR intervals.
///
/// Pure Dart, no Flutter imports, so it is unit-testable.
library;

class HeartRateMeasurement {
  const HeartRateMeasurement({
    required this.bpm,
    this.rrIntervalsMs = const [],
    this.energyExpendedKj,
    this.sensorContact,
  });

  final int bpm;

  /// RR intervals converted from 1/1024 s to milliseconds.
  final List<double> rrIntervalsMs;
  final int? energyExpendedKj;

  /// null when the sensor does not report contact status.
  final bool? sensorContact;

  @override
  String toString() => 'HeartRateMeasurement(bpm: $bpm, rr: $rrIntervalsMs, '
      'energy: $energyExpendedKj, contact: $sensorContact)';
}

class HeartRateParseException implements Exception {
  HeartRateParseException(this.message);
  final String message;
  @override
  String toString() => 'HeartRateParseException: $message';
}

HeartRateMeasurement parseHeartRateMeasurement(List<int> data) {
  if (data.isEmpty) throw HeartRateParseException('empty packet');
  final flags = data[0];
  final hr16 = flags & 0x01 != 0;
  final contactSupported = flags & 0x04 != 0;
  final energyPresent = flags & 0x08 != 0;
  final rrPresent = flags & 0x10 != 0;

  var i = 1;
  int u16(String field) {
    if (i + 2 > data.length) throw HeartRateParseException('packet too short for $field');
    final v = data[i] | (data[i + 1] << 8);
    i += 2;
    return v;
  }

  final int bpm;
  if (hr16) {
    bpm = u16('uint16 HR');
  } else {
    if (data.length < 2) throw HeartRateParseException('packet too short for uint8 HR');
    bpm = data[1];
    i = 2;
  }

  final energy = energyPresent ? u16('energy expended') : null;

  final rr = <double>[];
  if (rrPresent) {
    // Each RR is a uint16; a trailing odd byte is ignored.
    while (i + 2 <= data.length) {
      rr.add(u16('RR interval') * 1000.0 / 1024.0);
    }
  }

  return HeartRateMeasurement(
    bpm: bpm,
    rrIntervalsMs: rr,
    energyExpendedKj: energy,
    sensorContact: contactSupported ? flags & 0x02 != 0 : null,
  );
}
