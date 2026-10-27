import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_training/recording/session_recorder.dart';
import 'package:live_training/sources/watch_motion_source.dart';

Map<String, Object> batch({double sent = 100.5, String placement = 'ankle'}) => {
  'type': 'motion',
  'source': 'apple_watch',
  'placement': placement,
  'sent': sent,
  't': [100.0, 100.01, 100.5],
  'x': [0.1, 0.2, 0.3],
  'y': [9.81, 9.9, 30.0],
  'z': [0.0, 0.0, 0.0],
};

void main() {
  test('parses a watch batch: m/s² samples with their age', () {
    final b = parseWatchBatch(batch())!;
    expect(b.placement, 'ankle');
    expect(b.samples.length, 3);
    expect(b.samples.every((s) => s.source == 'apple_watch' && s.kind == 'acc'), isTrue);
    expect(b.samples.map((s) => s.ageMs), [500, 490, 0]);
    expect(b.samples.last.y, 30.0);
  });

  test('ignores anything that is not a motion batch', () {
    expect(parseWatchBatch(null), isNull);
    expect(parseWatchBatch({'type': 'other'}), isNull);
    expect(parseWatchBatch({'type': 'motion', 'sent': 1.0, 't': 'x'}), isNull);
  });

  test('source emits samples and remembers the placement', () async {
    final events = StreamController<dynamic>();
    final source = WatchMotionSource(batches: events.stream);
    final got = <double>[];
    source.start().listen((s) => got.add(s.y!));
    events.add(batch(placement: 'shin'));
    await Future<void>.delayed(Duration.zero);
    expect(got, [9.81, 9.9, 30.0]);
    expect(source.placement, 'shin');
    await events.close();
    await source.stop();
  });

  test('recorder stamps a sample at the time it was measured (its age earlier)', () async {
    final dir = await Directory.systemTemp.createTemp('watch_test');
    addTearDown(() => dir.delete(recursive: true));
    final r = SessionRecorder(
      directory: dir,
      sessionId: 's',
      setup: const SessionSetup(sport: 'general', sessionType: 'training', placement: 'ankle'),
      appVersion: 't',
      deviceModel: 't',
    );
    await r.start();
    await Future<void>.delayed(const Duration(milliseconds: 700));
    for (final s in parseWatchBatch(batch())!.samples) {
      r.add(s);
    }
    await r.stop();
    final rows = r.csvFile.readAsLinesSync().where((l) => l.contains(',apple_watch,acc,')).toList();
    final t = rows.map((l) => int.parse(l.split(',').first)).toList();
    expect(t[2] - t[0], inInclusiveRange(495, 505), reason: 'spacing kept from the watch clock');
    expect(t[0], lessThan(400), reason: 'oldest sample placed ~500 ms before arrival');
  });
}
