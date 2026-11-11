import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../coach/live_coach.dart';
import '../coach/profiles.dart';
import '../recording/session_recorder.dart';
import '../services/settings_store.dart';
import '../sources/motion_source.dart';
import '../sources/sensor_link.dart';
import '../util/day_summary.dart';
import '../util/live_stats.dart';
import '../util/motion.dart';

/// One player in a squad session: their sensor, their own recording and their own coach.
class SquadPlayer {
  SquadPlayer(this.name);

  final String name;
  SensorLink? link;
  StreamSubscription<Sample>? _sub;

  // While a session runs
  SessionRecorder? recorder;
  LiveCoach? coach;
  SessionStats stats = SessionStats();
  final LiveMagnitude _live = LiveMagnitude();
  CoachCall? lastCall;

  bool get hasSensor => link != null;
  double get motion => _live.value;
  int get efforts => coach?.efforts.length ?? 0;
  int get fatigueEfforts => coach?.efforts.where((e) => e.fatigue).length ?? 0;
  double? get impactLoad => coach?.strikes?.impactLoad;

  /// The profile's actions so far (e.g. deliveries), when it defines them and the sensor is on a leg.
  int? get actions => coach?.actions?.actions.length;
  String? get actionsLabel => coach?.actions?.cfg.labelPlural;
}

/// A net session for several players on one phone. Each player with a sensor gets a normal session
/// file of their own (so reports, analysis and upload work unchanged), tagged with the player's name
/// and a shared group id.
class SquadController extends ChangeNotifier {
  SquadController(
    this.settings, {
    required this.directory,
    this.profiles,
    this.appVersion = '',
    this.deviceModel = '',
  }) {
    players = [for (final name in settings.squadPlayers) SquadPlayer(name)];
  }

  final SettingsStore settings;
  final Future<Directory> Function() directory;
  SportProfiles? profiles;
  final String appVersion;
  final String deviceModel;

  late List<SquadPlayer> players;
  String sport = 'general';
  String placement = 'ankle';
  String? groupId;
  Timer? _ticker;
  final Stopwatch _clock = Stopwatch();

  bool get isRecording => groupId != null;
  Duration get elapsed => _clock.elapsed;
  int get ready => players.where((p) => p.link?.state == SensorState.live).length;

  void setSetup({String? sport, String? placement}) {
    if (isRecording) return;
    this.sport = sport ?? this.sport;
    this.placement = placement ?? this.placement;
    notifyListeners();
  }

  void addPlayer(String name) {
    final clean = name.trim();
    if (clean.isEmpty || players.any((p) => p.name == clean)) return;
    players.add(SquadPlayer(clean));
    _save();
  }

  Future<void> removePlayer(SquadPlayer p) async {
    if (isRecording) return;
    await unassign(p);
    players.remove(p);
    _save();
  }

  void _save() {
    settings.squadPlayers = [for (final p in players) p.name];
    notifyListeners();
  }

  /// Gives [player] a sensor and starts listening to it. A sensor belongs to one player at a time.
  Future<void> assign(SquadPlayer player, SensorLink link) async {
    for (final other in players.where((p) => p.link?.sensor.id == link.sensor.id)) {
      await unassign(other);
    }
    await unassign(player);
    player.link = link;
    link.addListener(notifyListeners);
    player._sub = link.start().listen((s) => _onSample(player, s));
    notifyListeners();
  }

  Future<void> unassign(SquadPlayer player) async {
    final link = player.link;
    if (link == null) return;
    await player._sub?.cancel();
    link.removeListener(notifyListeners);
    await link.stop();
    player.link = null;
    notifyListeners();
  }

  void _onSample(SquadPlayer p, Sample s) {
    if (s.kind == 'acc') p._live.add(s.x!, s.y!, s.z!, _liveMs - s.ageMs);
    final r = p.recorder;
    if (r == null || !r.isRecording) return;
    r.add(s);
    if (s.kind == 'acc') p.coach?.addAcc(r.elapsed.inMilliseconds - s.ageMs, s.x!, s.y!, s.z!);
  }

  final Stopwatch _liveClock = Stopwatch()..start();
  int get _liveMs => _liveClock.elapsedMilliseconds;

  Future<void> start() async {
    if (isRecording) return;
    final dir = await directory();
    final id = const Uuid().v4();
    final profile = profiles?.forSport(sport);
    for (final p in players.where((p) => p.hasSensor)) {
      final r = SessionRecorder(
        directory: dir,
        sessionId: const Uuid().v4(),
        setup: SessionSetup(
          sport: sport,
          sessionType: 'training',
          placement: placement,
          athleteId: settings.athleteId,
          extra: {'player': p.name, 'group_id': id},
        ),
        appVersion: appVersion,
        deviceModel: deviceModel,
      );
      await r.start();
      p
        ..recorder = r
        ..stats = SessionStats()
        ..lastCall = null
        ..coach = profile == null ? null : LiveCoach(CoachConfig.fromProfile(profile, placement));
    }
    groupId = id;
    _clock
      ..reset()
      ..start();
    _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) => tick());
    notifyListeners();
  }

  /// Advances every player's coach (5×/s while recording).
  @visibleForTesting
  void tick() {
    for (final p in players) {
      final r = p.recorder, c = p.coach;
      if (r == null || !r.isRecording) continue;
      p.stats.addMotion(p.motion, 0.2);
      for (final call in c?.tick(r.elapsed.inMilliseconds) ?? const <CoachCall>[]) {
        p.lastCall = call;
        r.markEvent(call.eventLabel);
        if (call.type == CallType.fatigue) unawaited(HapticFeedback.heavyImpact());
      }
    }
    notifyListeners();
  }

  /// Marks an event (e.g. a delivery) in one player's recording.
  void mark(SquadPlayer p, String label) => p.recorder?.markEvent(label);

  Future<void> stop() async {
    if (!isRecording) return;
    _ticker?.cancel();
    _clock.stop();
    for (final p in players) {
      final r = p.recorder;
      if (r == null) continue;
      for (final call in p.coach?.finish() ?? const <CoachCall>[]) {
        r.markEvent(call.eventLabel);
      }
      await r.stop(
        summary: SessionSummary(
          load: p.stats.load,
          efforts: p.efforts,
          fatigueEfforts: p.fatigueEfforts,
          impactLoad: p.coach?.strikes?.impactLoad,
          strikes: p.coach?.strikes?.strikes,
          actions: p.coach?.actions?.actions.length,
          actionsLabel: p.coach?.actions?.cfg.labelPlural,
          firstActionG: p.coach?.actions?.firstPeakG,
          lastActionG: p.coach?.actions?.lastPeakG,
        ).toJson(),
      );
      p.recorder = null;
    }
    groupId = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    for (final p in players) {
      p._sub?.cancel();
      p.link?.stop();
    }
    super.dispose();
  }
}
