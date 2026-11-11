import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'coach/advice.dart';
import 'coach/coach_context.dart';
import 'coach/live_coach.dart';
import 'coach/profiles.dart';
import 'config.dart';
import 'recording/session_recorder.dart';
import 'report/session_report.dart';
import 'services/backend_api.dart';
import 'services/session_store.dart';
import 'services/settings_store.dart';
import 'sources/motion_source.dart';
import 'sources/phone_motion_source.dart';
import 'sources/sensor_link.dart';
import 'sources/watch_motion_source.dart';
import 'sources/whoop_hr_source.dart';
import 'util/day_summary.dart';
import 'util/trends.dart';
import 'util/live_stats.dart';
import 'util/motion.dart';

/// Owns the sources and the recorder. Each source has ONE subscription, fanned out to the live
/// readouts and (while recording) to the recorder. The UI refreshes at 5 Hz (one tick).
class AppController extends ChangeNotifier {
  AppController(
    this.settings, {
    MotionSource? motionSource,
    WhoopHrSource? hrSource,
    WatchMotionSource? watchSource,
    SensorLink Function(FoundSensor sensor)? sensorLinkFactory,
    SensorScanner? sensorScanner,
  }) : motionSource = motionSource ?? PhoneMotionSource(),
       hr = hrSource ?? WhoopHrSource(),
       watch = watchSource ?? WatchMotionSource(),
       _linkFor = sensorLinkFactory ?? SensorLink.new,
       _scanner = sensorScanner {
    sport = settings.sport;
    sessionType = settings.sessionType;
    placement = settings.placement;
  }

  final SettingsStore settings;
  final MotionSource motionSource;
  final WhoopHrSource hr;

  /// Live motion from our watch app on the leg. While it flows, the coach and the Motion card use
  /// it instead of the phone (the phone keeps recording as a backup).
  final WatchMotionSource watch;

  /// Our leg sensor, when one is connected. It is the motion that counts: while it streams, the
  /// coach, the Motion card and the session's placement follow it (phone and watch keep recording).
  SensorLink? sensor;
  final SensorLink Function(FoundSensor sensor) _linkFor;
  final SensorScanner? _scanner;
  StreamSubscription<Sample>? _sensorSub;
  final LiveMagnitude _liveSensor = LiveMagnitude();
  int? _lastSensorMs;
  final List<(int, double)> _sensorRecent = []; // (live ms, total g) over the last 3 s
  bool get sensorLive => _lastSensorMs != null && _liveClock.elapsedMilliseconds - _lastSensorMs! < motionStaleMs;

  /// Samples per second from the sensor over the last 3 s (0 when it stopped).
  double get sensorRateHz {
    if (!sensorLive || _sensorRecent.length < 2) return 0;
    final span = (_sensorRecent.last.$1 - _sensorRecent.first.$1) / 1000;
    return span <= 0 ? 0 : (_sensorRecent.length - 1) / span;
  }

  /// Hardest total acceleration in the last 3 s, in g (gravity included: standing still is 1 g).
  double? get sensorPeakG =>
      !sensorLive || _sensorRecent.isEmpty ? null : _sensorRecent.map((e) => e.$2).reduce((a, b) => a > b ? a : b);

  // Per-session choices (defaults come from Settings, editable on Home before Start).
  late String sport;
  late String sessionType;
  late String placement;
  String notes = '';

  // Live readouts
  final LiveMagnitude _live = LiveMagnitude();
  final Stopwatch _liveClock = Stopwatch()..start();
  final LiveMagnitude _liveWatch = LiveMagnitude();
  int? _lastWatchMs;
  bool get watchLive => _lastWatchMs != null && _liveClock.elapsedMilliseconds - _lastWatchMs! < motionStaleMs;
  double get motionMagnitude => sensorLive
      ? _liveSensor.value
      : watchLive
      ? _liveWatch.value
      : _live.value;
  String? motionError;
  bool motionErrorNeedsSettings = false;
  int _lastAccMs = 0;
  bool _motionPermissionDenied = false;
  static const motionStaleMs = 3000;

  // Recent history for the sparklines (one point per UI tick).
  static const tick = Duration(milliseconds: 200);
  final RollingSeries hrHistory = RollingSeries(120 * 5); // 2 min
  final RollingSeries motionHistory = RollingSeries(60 * 5); // 1 min

  /// Running numbers for the session being recorded.
  SessionStats stats = SessionStats();

  // Recovery card
  Recovery? recovery;
  String? recoveryError;
  bool recoveryLoading = false;

  // Live calls (sport profile from assets/sport_profiles.yaml)
  SportProfiles? _profiles;
  SportProfiles? get profiles => _profiles;
  LiveCoach? coach;
  final List<CoachCall> calls = [];

  // Today card: WHOOP day strain plus our sessions of the day
  DayStrain? dayStrain;
  DaySummary get today => DaySummary.of(sessions.map((s) => s.dayEntry).whereType<DayEntry>(), DateTime.now());

  /// The last 4 weeks, for the Sessions tab's week card and the Trends screen.
  Trends get trends => Trends.of(sessions.map((s) => s.dayEntry).whereType<DayEntry>(), DateTime.now());

  // Recording
  SessionRecorder? recorder;
  bool get isRecording => recorder?.isRecording ?? false;

  // Sessions screen
  List<LocalSession> sessions = [];
  final Map<String, String> uploadStatus = {}; // session id -> status text
  final Set<String> uploading = {};

  StreamSubscription<Sample>? _motionSub;
  StreamSubscription<Sample>? _hrSub;
  StreamSubscription<Sample>? _watchSub;
  Timer? _uiTimer;

  /// OS name and version from dart:io, e.g. "ios Version 18.5 (Build 22F76)". No plugin needed
  /// (device_info_plus 12.4+ needs the Xcode 26 SDK to build).
  final String _deviceModel = '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';

  BackendApi get api => BackendApi(settings.backendUrl);

  Future<void> init() async {
    await _loadProfiles();
    _motionPermissionDenied = await _isMotionPermissionDenied();
    _motionSub = motionSource.start().listen(
      _onMotion,
      onError: (Object e) {
        motionError = 'Motion sensor error: $e';
      },
    );
    _hrSub = hr.samples.listen(_onSample);
    _watchSub = watch.start().listen(_onWatch);
    hr.addListener(notifyListeners);
    _uiTimer = Timer.periodic(tick, (_) {
      _checkMotionFlowing();
      hrHistory.add(hr.lastBpm?.toDouble());
      motionHistory.add(motionError == null ? motionMagnitude : null);
      if (isRecording) {
        stats.addMotion(motionMagnitude, tick.inMilliseconds / 1000);
        _deliver(coach?.tick(recorder!.elapsed.inMilliseconds) ?? const []);
      }
      notifyListeners();
    });
    await refreshSessions();
    if (whoopEnabled) unawaited(refreshRecovery());
    final id = settings.sensorId;
    if (id != null) unawaited(connectSensor(FoundSensor(id, settings.sensorName ?? 'Sensor')));
  }

  // ---- our leg sensor ---------------------------------------------------------

  /// Bluetooth permission (Android asks at run time; iOS shows its own prompt on first use).
  /// Returns false and explains in [bluetoothError] when it is refused.
  Future<bool> _bluetoothAllowed() async {
    if (!Platform.isAndroid) return true;
    // Android 12+ needs scan/connect; Android 11 and older needs location to scan instead.
    // Requesting all three works on every version without knowing the SDK level:
    // - on Android 11 and older, permission_handler reports scan/connect as granted;
    // - on Android 12+, location is not in the manifest (maxSdkVersion 30), so no dialog appears.
    final results = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
    return results[Permission.bluetoothScan]!.isGranted && results[Permission.bluetoothConnect]!.isGranted;
  }

  String? bluetoothError;

  /// Leg sensors nearby (about 5 s).
  Future<List<FoundSensor>> scanSensors() async {
    if (!await _bluetoothAllowed()) {
      bluetoothError =
          'Bluetooth permission denied. Allow "Nearby devices" in Settings › Apps › Live Training › Permissions.';
      notifyListeners();
      return const [];
    }
    bluetoothError = null;
    return (_scanner ?? SensorScanner()).scan();
  }

  /// Connects to [found], remembers it for next time, and keeps reconnecting if it drops.
  Future<void> connectSensor(FoundSensor found) async {
    if (isRecording && sensor != null) return; // don't swap sensors mid-session
    await disconnectSensor(forget: false);
    if (!await _bluetoothAllowed()) {
      bluetoothError =
          'Bluetooth permission denied. Allow "Nearby devices" in Settings › Apps › Live Training › Permissions.';
      notifyListeners();
      return;
    }
    settings.rememberSensor(found.id, found.name);
    final link = _linkFor(found);
    sensor = link;
    link.addListener(notifyListeners);
    _sensorSub = link.start().listen(_onSensor);
    // A leg sensor isn't in a phone armband or pocket: default the placement to the ankle.
    if (placement.startsWith('phone')) placement = 'ankle';
    notifyListeners();
  }

  Future<void> disconnectSensor({bool forget = true}) async {
    final link = sensor;
    if (link == null) {
      if (forget) settings.rememberSensor(null, null);
      return;
    }
    if (isRecording && forget) return;
    sensor = null;
    await _sensorSub?.cancel();
    _sensorSub = null;
    link.removeListener(notifyListeners);
    await link.stop();
    _lastSensorMs = null;
    _sensorRecent.clear();
    if (forget) settings.rememberSensor(null, null);
    notifyListeners();
  }

  void _onSensor(Sample s) {
    recorder?.add(s);
    if (s.kind != 'acc') return;
    final now = _liveClock.elapsedMilliseconds;
    _lastSensorMs = now;
    final x = s.x!, y = s.y!, z = s.z!;
    _liveSensor.add(x, y, z, now - s.ageMs);
    _sensorRecent.add((now - s.ageMs, math.sqrt(x * x + y * y + z * z) / gravity));
    while (_sensorRecent.isNotEmpty && _sensorRecent.first.$1 < now - 3000) {
      _sensorRecent.removeAt(0);
    }
    final c = coach;
    if (!isRecording || c == null) return;
    c.addAcc(recorder!.elapsed.inMilliseconds - s.ageMs, x, y, z);
  }

  /// Feeds one sample as if it came from our sensor (widget tests and previews).
  @visibleForTesting
  void debugAddSensor(Sample s) => _onSensor(s);

  /// Feeds one sample as if it came from the motion source (widget tests and previews).
  @visibleForTesting
  void debugAddMotion(Sample s) => _onMotion(s);

  @visibleForTesting
  void debugAddWatch(Sample s) => _onWatch(s);

  /// Watch samples arrive in batches; each knows its age, so it is placed at its own time.
  void _onWatch(Sample s) {
    if (s.kind != 'acc') return;
    final now = _liveClock.elapsedMilliseconds;
    _lastWatchMs = now;
    _liveWatch.add(s.x!, s.y!, s.z!, now - s.ageMs);
    recorder?.add(s);
    final c = coach;
    if (!isRecording || c == null || sensor != null) return; // a connected sensor owns the coach
    c.addAcc(recorder!.elapsed.inMilliseconds - s.ageMs, s.x!, s.y!, s.z!);
  }

  void _onMotion(Sample s) {
    if (s.kind == 'acc') {
      _lastAccMs = _liveClock.elapsedMilliseconds;
      _live.add(s.x!, s.y!, s.z!, _lastAccMs);
    }
    _onSample(s);
  }

  /// iOS: the raw accelerometer works without Motion & Fitness access, so this only *explains* a
  /// missing motion stream; it never blocks recording. (permission_handler reports "not asked yet"
  /// as denied on iOS, so only permanentlyDenied/restricted count.)
  Future<bool> _isMotionPermissionDenied() async {
    if (!Platform.isIOS) return false;
    try {
      final status = await Permission.sensors.status;
      return status.isPermanentlyDenied || status.isRestricted;
    } on Exception {
      return false;
    }
  }

  /// Shows an error when no accelerometer data has arrived for a few seconds, and clears it when
  /// data flows again.
  void _checkMotionFlowing() {
    final stale = _liveClock.elapsedMilliseconds - _lastAccMs > motionStaleMs;
    final String? message = !stale
        ? null
        : _motionPermissionDenied
        ? 'No motion data: Motion & Fitness access is off for Live Training. Turn it on in '
              'Settings › Privacy & Security › Motion & Fitness.'
        : 'No motion data from the phone\'s sensors. Keep the app open on screen; if this stays, '
              'force-quit and reopen the app.';
    if (message != motionError && (stale || motionError != null)) {
      motionError = message;
      motionErrorNeedsSettings = stale && _motionPermissionDenied;
    }
  }

  void _onSample(Sample s) {
    recorder?.add(s);
    if (!isRecording) return;
    if (s.kind == 'hr') stats.addHr(s.value!);
    final c = coach;
    if (c == null) return;
    final tMs = recorder!.elapsed.inMilliseconds;
    // A leg wins: the connected sensor (even while it reconnects: its thresholds aren't the phone's),
    // else the watch while it streams.
    if (s.kind == 'acc' && sensor == null && !watchLive) c.addAcc(tMs, s.x!, s.y!, s.z!);
    if (s.kind == 'hr') c.addHr(tMs, s.value!);
  }

  // ---- live calls -----------------------------------------------------------

  Future<void> _loadProfiles() async {
    try {
      _profiles = SportProfiles.parse(await rootBundle.loadString('assets/sport_profiles.yaml'));
    } on Object catch (e) {
      debugPrint('Sport profiles not loaded, live calls off: $e');
    }
  }

  /// Shows, buzzes and records each call as an event in the session file.
  void _deliver(List<CoachCall> newCalls) {
    for (final call in newCalls) {
      calls.add(call);
      recorder?.markEvent(call.eventLabel);
      unawaited(call.important ? HapticFeedback.heavyImpact() : HapticFeedback.lightImpact());
    }
  }

  // ---- WHOOP HR -------------------------------------------------------------

  Future<void> connectHr() async {
    if (!await _bluetoothAllowed()) {
      hr.reportError(
        'Bluetooth permission denied. Allow "Nearby devices" in Settings › Apps › Live Training › Permissions.',
        needsSettings: true,
      );
      return;
    }
    await hr.connect();
  }

  Future<void> disconnectHr() => hr.disconnect();

  // ---- recovery -------------------------------------------------------------

  Future<void> refreshRecovery() async {
    if (!whoopEnabled) return;
    final id = settings.athleteId;
    if (settings.backendUrl.isEmpty) {
      recovery = null;
      recoveryError = 'Add your backend URL in Settings to see today\'s recovery.';
      notifyListeners();
      return;
    }
    if (id == null) {
      recovery = null;
      recoveryError = 'Set your athlete ID in Settings to see today\'s recovery.';
      notifyListeners();
      return;
    }
    recoveryLoading = true;
    notifyListeners();
    try {
      try {
        recovery = await api.latestRecovery(id);
        recoveryError = null;
      } on BackendException catch (e) {
        recoveryError = e.message;
      }
      try {
        dayStrain = await api.latestCycle(id);
      } on BackendException {
        dayStrain = null; // the Today card still shows our own numbers
      }
    } finally {
      recoveryLoading = false;
      notifyListeners();
    }
  }

  // ---- session --------------------------------------------------------------

  void updateSetup({String? sport, String? sessionType, String? placement, String? notes}) {
    if (isRecording) return;
    this.sport = sport ?? this.sport;
    this.sessionType = sessionType ?? this.sessionType;
    this.placement = placement ?? this.placement;
    this.notes = notes ?? this.notes;
    notifyListeners();
  }

  Future<void> startSession() async {
    if (isRecording) return;
    // With the watch streaming (and not our sensor), the motion that counts is the watch's: use where it is worn.
    final sessionPlacement = sensor == null && watchLive ? (watch.placement ?? placement) : placement;
    final r = SessionRecorder(
      directory: await SessionStore.directory(),
      sessionId: const Uuid().v4(),
      setup: SessionSetup(
        sport: sport,
        sessionType: sessionType,
        placement: sessionPlacement,
        athleteId: settings.athleteId,
        notes: notes,
      ),
      appVersion: appVersion,
      deviceModel: _deviceModel,
    );
    await r.start();
    stats = SessionStats();
    recorder = r;
    calls.clear();
    final profiles = _profiles;
    final cfg = profiles == null ? null : CoachConfig.fromProfile(profiles.forSport(sport), sessionPlacement);
    coach = cfg == null
        ? null
        : LiveCoach(
            cfg,
            restingHr: recovery?.restingHr,
            recoveryScore: recovery?.recoveryScore,
            actionBaselineG: cfg.actions == null
                ? null
                : actionBaseline(
                    sessions.map((s) => s.dayEntry).whereType<DayEntry>(),
                    sport,
                    minSessions: cfg.actions!.baselineSessions,
                  ),
          );
    _deliver(coach?.start() ?? const []);
    await WakelockPlus.enable();
    notifyListeners();
  }

  Future<void> stopSession() async {
    final r = recorder;
    if (r == null) return;
    final c = coach;
    _deliver(c?.finish() ?? const []); // an action still waiting to be confirmed
    await r.stop(
      summary: SessionSummary(
        load: stats.load,
        efforts: c?.efforts.length ?? 0,
        fatigueEfforts: c?.efforts.where((e) => e.fatigue).length ?? 0,
        hrAvg: stats.hrAvg,
        hrMax: stats.hrMax,
        impactLoad: c?.strikes?.impactLoad,
        strikes: c?.strikes?.strikes,
        actions: c?.actions?.actions.length,
        actionsLabel: c?.actions?.cfg.labelPlural,
        firstActionG: c?.actions?.firstPeakG,
        lastActionG: c?.actions?.lastPeakG,
      ).toJson(),
    );
    coach = null;
    await WakelockPlus.disable();
    notes = '';
    await refreshSessions();
    if (whoopEnabled) unawaited(refreshRecovery()); // WHOOP's day strain has moved
    notifyListeners();
  }

  void markEvent(String label) {
    recorder?.markEvent(label);
    notifyListeners();
  }

  // ---- sessions list --------------------------------------------------------

  Future<void> refreshSessions() async {
    try {
      sessions = await SessionStore.list();
    } on Exception {
      return; // storage unavailable (e.g. in widget tests); keep the current list
    }
    final done = settings.uploadedSessionIds;
    for (final s in sessions) {
      if (done.contains(s.id)) uploadStatus[s.id] = 'Uploaded';
    }
    notifyListeners();
  }

  // ---- AI coach ---------------------------------------------------------------

  /// Advice for the Live tab's Coach card: how the last session started (readiness from the sensor),
  /// then this week's load.
  List<Advice> get homeAdvice {
    final entries = sessions.map((s) => s.dayEntry).whereType<DayEntry>().toList();
    final profiles = _profiles;
    final actionCfg = profiles == null ? null : CoachConfig.fromProfile(profiles.forSport(sport), placement).actions;
    final start = actionCfg == null ? null : adviceForLatestStart(entries, sport, actionCfg);
    return [?start, ...adviceForWeek(trends)].take(3).toList();
  }

  /// Why the AI coach can't be used yet, or null when it can be tried.
  String? get coachNotSetUp => settings.backendUrl.isEmpty
      ? 'Add your server address in Settings › Upload server. The server needs a Claude API key '
            '(ANTHROPIC_API_KEY in backend/.env); the key stays on the server, never on the phone.'
      : null;

  /// The athlete's data for the coach: recent sessions, weeks, and one session in detail when asked about it.
  Map<String, dynamic> coachData({SessionReport? report, DateTime? startedAt}) => coachContext(
    sport: sport,
    placement: placement,
    entries: sessions.map((s) => s.dayEntry).whereType<DayEntry>(),
    trends: trends,
    session: report,
    sessionStartedAt: startedAt,
  );

  Future<String> askCoach(String question, Map<String, dynamic> context, List<Map<String, String>> history) =>
      api.askCoach(question, context, history);

  /// Deletes a finished session from the phone.
  Future<void> deleteSession(LocalSession s) async {
    if (isRecording && recorder?.sessionId == s.id) return;
    await SessionStore.delete(s);
    await refreshSessions();
  }

  bool isUploaded(String id) => settings.uploadedSessionIds.contains(id);

  Future<void> upload(LocalSession s) async {
    if (uploading.contains(s.id) || (isRecording && recorder!.sessionId == s.id)) return;
    uploading.add(s.id);
    uploadStatus[s.id] = 'Uploading…';
    notifyListeners();
    try {
      final result = await api.uploadSession(s.csv, s.metadataFile);
      settings.markUploaded(s.id);
      uploadStatus[s.id] = result == UploadResult.uploaded ? 'Uploaded' : 'Uploaded (already on server)';
    } on BackendException catch (e) {
      uploadStatus[s.id] = 'Failed: ${e.message}';
    } finally {
      uploading.remove(s.id);
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _uiTimer?.cancel();
    _motionSub?.cancel();
    _hrSub?.cancel();
    _watchSub?.cancel();
    _sensorSub?.cancel();
    sensor?.stop();
    motionSource.stop();
    watch.stop();
    hr.removeListener(notifyListeners);
    hr.dispose();
    super.dispose();
  }
}
