// Renders every screen at iPhone size with realistic data, idle and recording.
// Fails on layout overflow or any build exception.
//
// To also save PNG previews (with real fonts):
//   PREVIEW_DIR=/tmp/previews PREVIEW_FONT_DIR=/path/with/Inter-*.otf flutter test test/ui_screens_test.dart
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_training/app_controller.dart';
import 'package:live_training/main.dart';
import 'package:live_training/recording/session_recorder.dart';
import 'package:live_training/services/backend_api.dart';
import 'package:live_training/services/settings_store.dart';
import 'package:live_training/sources/motion_source.dart';
import 'package:live_training/sources/whoop_hr_source.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _NoMotion implements MotionSource {
  @override
  String get id => 'phone';
  @override
  Stream<Sample> start() => const Stream.empty();
  @override
  Future<void> stop() async {}
}

final _previewDir = Platform.environment['PREVIEW_DIR'];
final _fontDir = Platform.environment['PREVIEW_FONT_DIR'];

Future<void> _loadFonts() async {
  if (_fontDir == null) return;
  final family = FontLoader('Roboto'); // the default family the test platform asks for
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    final f = File('$_fontDir/Inter-$w.otf');
    if (f.existsSync()) family.addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
  }
  await family.load();
  final icons = File(
    '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  );
  if (icons.existsSync()) {
    await (FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())))).load();
  }
}

Future<AppController> _controller({required bool withData}) async {
  SharedPreferences.setMockInitialValues({
    if (withData) 'backend_url': 'http://172.20.10.2:8000',
    if (withData) 'athlete_id': 1,
    'sport': 'soccer',
    'placement': 'phone_armband',
  });
  final hr = WhoopHrSource();
  final c = AppController(await SettingsStore.load(), motionSource: _NoMotion(), hrSource: hr);
  if (!withData) {
    c.recoveryError = 'Add your backend URL in Settings to see today\'s recovery.';
    return c;
  }
  c.recovery = Recovery.fromJson({
    'score_state': 'SCORED',
    'recovery_score': 78,
    'resting_heart_rate': 52,
    'hrv_rmssd_milli': 84.3,
    'user_calibrating': false,
  });
  hr
    ..state = HrConnection.connected
    ..deviceName = 'WHOOP 5C00599707'
    ..lastBpm = 142;
  for (var i = 0; i < 600; i++) {
    c.hrHistory.add(128 + 18 * math.sin(i / 40) + 4 * math.sin(i / 7));
  }
  for (var i = 0; i < 300; i++) {
    final m = 2.2 + 1.6 * math.sin(i / 9).abs() + (i % 60 > 50 ? 6 : 0);
    c.motionHistory.add(m);
    c.debugAddMotion(Sample.vector('phone', 'acc', 0, 9.81 + m, 0));
  }
  return c;
}

Future<void> _pump(WidgetTester tester, AppController c, String name, {int tab = 0}) async {
  tester.view.physicalSize = const Size(1170, 2532 * 1.6); // iPhone width, tall enough to see the whole screen
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final key = GlobalKey();
  await tester.pumpWidget(
    RepaintBoundary(
      key: key,
      child: LiveTrainingApp(controller: c),
    ),
  );
  if (tab != 0) {
    await tester.tap(find.text(['LIVE', 'SESSIONS', 'SETTINGS'][tab]));
  }
  await tester.pump(const Duration(seconds: 1)); // ring animation
  expect(tester.takeException(), isNull);
  final dir = _previewDir;
  if (dir == null) return;
  await tester.runAsync(() async {
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory(dir).createSync(recursive: true);
    File('$dir/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
  });
}

void main() {
  setUpAll(_loadFonts);

  testWidgets('home, first run (nothing connected)', (tester) async {
    await _pump(tester, await _controller(withData: false), 'home_empty');
  });

  testWidgets('home, connected', (tester) async {
    await _pump(tester, await _controller(withData: true), 'home_connected');
  });

  testWidgets('home, recording', (tester) async {
    final c = await _controller(withData: true);
    final dir = Directory.systemTemp.createTempSync('ui_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    await tester.runAsync(() async {
      final r = SessionRecorder(
        directory: dir,
        sessionId: '00000000-0000-0000-0000-000000000001',
        setup: const SessionSetup(sport: 'soccer', sessionType: 'training', placement: 'phone_armband'),
        appVersion: 'test',
        deviceModel: 'test',
      );
      await r.start();
      r.markEvent('sync_jumps');
      c.recorder = r;
    });
    for (final bpm in [120.0, 151.0, 168.0, 144.0]) {
      c.stats.addHr(bpm);
    }
    c.stats.load = 14.6;
    await _pump(tester, c, 'home_recording');
    await tester.runAsync(() => c.recorder!.stop());
  });

  testWidgets('sessions, empty', (tester) async {
    await _pump(tester, await _controller(withData: false), 'sessions', tab: 1);
  });

  testWidgets('settings', (tester) async {
    await _pump(tester, await _controller(withData: true), 'settings', tab: 2);
  });
}
