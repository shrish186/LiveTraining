import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_training/coach/profiles.dart';
import 'package:live_training/services/session_store.dart';
import 'package:live_training/services/settings_store.dart';
import 'package:live_training/sources/sensor_link.dart';
import 'package:live_training/squad/squad_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One stream packet of 10 samples at 100 Hz, all with the same vertical acceleration (in milli-g).
List<int> packet(int seq, int firstMs, int mg) {
  final b = ByteData(12 + 60)
    ..setUint8(0, 1)
    ..setUint16(2, seq, Endian.little)
    ..setUint32(4, firstMs, Endian.little)
    ..setUint16(8, 10000, Endian.little)
    ..setUint8(10, 10)
    ..setUint8(11, 1);
  for (var i = 0; i < 10; i++) {
    b.setInt16(12 + i * 6 + 2, mg, Endian.little);
  }
  return b.buffer.asUint8List();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('two players, two sensors: each gets their own session file with their own motion', () async {
    SharedPreferences.setMockInitialValues({});
    final dir = await Directory.systemTemp.createTemp('squad_test');
    addTearDown(() => dir.delete(recursive: true));
    final squad = SquadController(
      await SettingsStore.load(),
      directory: () async => dir,
      profiles: SportProfiles.parse(File('assets/sport_profiles.yaml').readAsStringSync()),
    );
    squad
      ..addPlayer('Arjun')
      ..addPlayer('Sam')
      ..addPlayer('Arjun'); // duplicate ignored
    expect(squad.players.map((p) => p.name), ['Arjun', 'Sam']);
    expect(squad.settings.squadPlayers, ['Arjun', 'Sam']);

    final a = StreamController<List<int>>(), b = StreamController<List<int>>();
    await squad.assign(squad.players[0], SensorLink(const FoundSensor('A', 'LT-000A'), packets: a.stream));
    await squad.assign(squad.players[1], SensorLink(const FoundSensor('B', 'LT-000B'), packets: b.stream));

    await squad.start();
    expect(squad.isRecording, isTrue);
    // Arjun works hard (3 g), Sam stands still (1 g).
    for (var k = 0; k < 30; k++) {
      a.add(packet(k, k * 100, 3000));
      b.add(packet(k, k * 100, 1000));
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
    squad.tick();
    expect(squad.ready, 2);
    expect(squad.players[0].motion, greaterThan(squad.players[1].motion + 5));
    await squad.stop();
    expect(squad.isRecording, isFalse);

    final sessions = await () async {
      final out = <LocalSession>[];
      for (final f in dir.listSync().whereType<File>().where((f) => f.path.endsWith('.json'))) {
        final meta = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
        out.add(LocalSession(meta['session_id'] as String, File(f.path.replaceAll('.json', '.csv')), f, meta));
      }
      return out;
    }();
    expect(sessions.map((s) => s.player), unorderedEquals(['Arjun', 'Sam']));
    expect(sessions.map((s) => s.metadata['group_id']).toSet().length, 1, reason: 'one shared group id');
    expect(sessions.every((s) => s.metadata['placement'] == 'ankle' && s.metadata['complete'] == true), isTrue);
    expect(sessions.every((s) => s.dayEntry == null), isTrue, reason: "not the phone owner's own training");
    for (final s in sessions) {
      final rows = s.csv.readAsLinesSync().where((l) => l.contains(',xiao,acc,')).toList();
      expect(rows.length, 300);
      final y = double.parse(rows.first.split(',')[4]);
      expect(y, closeTo(s.player == 'Arjun' ? 29.43 : 9.81, 0.01));
    }
  });

  test('a sensor moves to another player when reassigned', () async {
    SharedPreferences.setMockInitialValues({
      'squad_players': ['A', 'B'],
    });
    final squad = SquadController(await SettingsStore.load(), directory: () async => Directory.systemTemp);
    final link = SensorLink(const FoundSensor('X', 'LT-000X'), packets: const Stream.empty());
    await squad.assign(squad.players[0], link);
    await squad.assign(squad.players[1], SensorLink(const FoundSensor('X', 'LT-000X'), packets: const Stream.empty()));
    expect(squad.players[0].hasSensor, isFalse);
    expect(squad.players[1].hasSensor, isTrue);
  });
}
