import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_training/recording/session_recorder.dart';
import 'package:live_training/sources/motion_source.dart';
import 'package:live_training/util/motion.dart';

void main() {
  late Directory dir;

  setUp(() async => dir = await Directory.systemTemp.createTemp('recorder_test'));
  tearDown(() async => dir.delete(recursive: true));

  SessionRecorder make() => SessionRecorder(
        directory: dir,
        sessionId: '4f6c2b0e-3f7a-4d2f-9f0e-6a1f5d2b7c11',
        setup: const SessionSetup(sport: 'soccer', sessionType: 'drill', placement: 'shin', athleteId: 3),
        appVersion: '0.1.0',
        deviceModel: 'test',
        clock: () => DateTime.utc(2026, 10, 27, 18, 2, 11, 456),
      );

  test('writes a valid CSV and metadata JSON', () async {
    final r = make();
    await r.start();
    expect(r.metadataFile.existsSync(), isTrue, reason: 'metadata is written at start too');
    expect(jsonDecode(r.metadataFile.readAsStringSync())['complete'], isFalse);

    for (var i = 0; i < 1200; i++) {
      r.add(Sample.vector('phone', 'acc', 0, 9.81, i.toDouble()));
    }
    r.add(const Sample.scalar('whoop_hr', 'hr', 120));
    r.add(const Sample.scalar('whoop_hr', 'rr', 500));
    r.markEvent('sync_jumps');
    await r.stop();
    r.add(const Sample.scalar('whoop_hr', 'hr', 1)); // ignored after stop

    final lines = r.csvFile.readAsLinesSync();
    expect(lines.first, 't_ms,source,kind,x,y,z,value');
    expect(lines[1], '0,phone,event,,,,session_start');
    expect(lines.last, endsWith(',phone,event,,,,session_end'));
    expect(lines.length, 1 + 1200 + 2 + 3); // header, acc, hr+rr, 3 events
    expect(lines.where((l) => l.contains(',hr,')).single, endsWith(',whoop_hr,hr,,,,120'));
    final times = lines.skip(1).map((l) => int.parse(l.split(',').first)).toList();
    for (var i = 1; i < times.length; i++) {
      expect(times[i], greaterThanOrEqualTo(times[i - 1]), reason: 'one monotonic clock');
    }

    final meta = jsonDecode(r.metadataFile.readAsStringSync()) as Map<String, dynamic>;
    expect(meta['session_id'], '4f6c2b0e-3f7a-4d2f-9f0e-6a1f5d2b7c11');
    expect(meta['athlete_id'], 3);
    expect(meta['sport'], 'soccer');
    expect(meta['session_type'], 'drill');
    expect(meta['placement'], 'shin');
    expect(meta['started_at'], '2026-10-27T18:02:11.456Z');
    expect(meta['complete'], isTrue);
    final sources = {for (final s in meta['sources'] as List) s['id']: s};
    expect(sources.keys, unorderedEquals(['phone', 'whoop_hr']));
    expect(sources['whoop_hr']['kinds'], ['hr', 'rr']);
    expect(r.count('phone', 'acc'), 1200);
    expect(r.events, ['session_start', 'sync_jumps', 'session_end']);
  });

  test('ignores samples before start', () async {
    final r = make();
    r.add(const Sample.scalar('whoop_hr', 'hr', 60));
    expect(r.counts, isEmpty);
  });

  group('motion', () {
    test('dynamic magnitude removes gravity', () {
      expect(dynamicMagnitude(0, 9.81, 0), closeTo(0, 1e-9));
      expect(dynamicMagnitude(0, 0, 0), closeTo(9.81, 1e-9));
      expect(dynamicMagnitude(0, 19.81, 0), closeTo(10, 1e-9));
    });

    test('live magnitude follows a step with the time constant', () {
      final live = LiveMagnitude(timeConstantMs: 500);
      live.add(0, 9.81, 0, 0);
      var t = 0;
      for (; t <= 500; t += 10) {
        live.add(0, 19.81, 0, t);
      }
      expect(live.value, inInclusiveRange(5.5, 7.0)); // ~63% after one time constant
      for (; t <= 5000; t += 10) {
        live.add(0, 19.81, 0, t);
      }
      expect(live.value, closeTo(10, 0.05));
    });
  });
}
