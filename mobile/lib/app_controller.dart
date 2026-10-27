import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'config.dart';
import 'recording/session_recorder.dart';
import 'services/backend_api.dart';
import 'services/session_store.dart';
import 'services/settings_store.dart';
import 'sources/motion_source.dart';
import 'sources/phone_motion_source.dart';
import 'sources/whoop_hr_source.dart';
import 'util/motion.dart';

/// Owns the sources and the recorder. Each source has ONE subscription, fanned out to the live
/// readouts and (while recording) to the recorder. UI refreshes are throttled to 5 Hz.
class AppController extends ChangeNotifier {
  AppController(this.settings, {MotionSource? motionSource, WhoopHrSource? hrSource})
      : motionSource = motionSource ?? PhoneMotionSource(),
        hr = hrSource ?? WhoopHrSource() {
    sport = settings.sport;
    sessionType = settings.sessionType;
    placement = settings.placement;
  }

  final SettingsStore settings;
  final MotionSource motionSource;
  final WhoopHrSource hr;

  // Per-session choices (defaults come from Settings, editable on Home before Start).
  late String sport;
  late String sessionType;
  late String placement;
  String notes = '';

  // Live readouts
  final LiveMagnitude _live = LiveMagnitude();
  final Stopwatch _liveClock = Stopwatch()..start();
  double get motionMagnitude => _live.value;
  String? motionError;
  bool motionErrorNeedsSettings = false;
  int _lastAccMs = 0;
  bool _motionPermissionDenied = false;
  static const motionStaleMs = 3000;

  // Recovery card
  Recovery? recovery;
  String? recoveryError;
  bool recoveryLoading = false;

  // Recording
  SessionRecorder? recorder;
  bool get isRecording => recorder?.isRecording ?? false;

  // Sessions screen
  List<LocalSession> sessions = [];
  final Map<String, String> uploadStatus = {}; // session id -> status text
  final Set<String> uploading = {};

  StreamSubscription<Sample>? _motionSub;
  StreamSubscription<Sample>? _hrSub;
  Timer? _uiTimer;
  bool _dirty = false;
  /// OS name and version from dart:io, e.g. "ios Version 18.5 (Build 22F76)". No plugin needed
  /// (device_info_plus 12.4+ needs the Xcode 26 SDK to build).
  final String _deviceModel = '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';

  BackendApi get api => BackendApi(settings.backendUrl);

  Future<void> init() async {
    _motionPermissionDenied = await _isMotionPermissionDenied();
    _motionSub = motionSource.start().listen(_onMotion, onError: (Object e) {
      motionError = 'Motion sensor error: $e';
      _dirty = true;
    });
    _hrSub = hr.samples.listen(_onSample);
    hr.addListener(notifyListeners);
    _uiTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      _checkMotionFlowing();
      if (_dirty || isRecording) {
        _dirty = false;
        notifyListeners();
      }
    });
    await refreshSessions();
    unawaited(refreshRecovery());
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
      _dirty = true;
    }
  }

  void _onSample(Sample s) {
    recorder?.add(s);
    _dirty = true;
  }

  // ---- WHOOP HR -------------------------------------------------------------

  Future<void> connectHr() async {
    if (Platform.isAndroid) {
      // Android 12+ needs scan/connect; Android 11 and older needs location to scan instead.
      // Requesting all three works on every version without knowing the SDK level:
      // - on Android 11 and older, permission_handler reports scan/connect as granted;
      // - on Android 12+, location is not in the manifest (maxSdkVersion 30), so no dialog appears.
      // Only scan/connect are required here; a missing location shows up as a scan error.
      final results = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.locationWhenInUse,
      ].request();
      if (!results[Permission.bluetoothScan]!.isGranted || !results[Permission.bluetoothConnect]!.isGranted) {
        hr.reportError(
          'Bluetooth permission denied. Allow "Nearby devices" in Settings › Apps › Live Training › Permissions.',
          needsSettings: true,
        );
        return;
      }
    }
    // iOS shows its Bluetooth prompt by itself on first use.
    await hr.connect();
  }

  Future<void> disconnectHr() => hr.disconnect();

  // ---- recovery -------------------------------------------------------------

  Future<void> refreshRecovery() async {
    final id = settings.athleteId;
    if (id == null) {
      recovery = null;
      recoveryError = 'Set your athlete ID in Settings to see today\'s recovery.';
      notifyListeners();
      return;
    }
    recoveryLoading = true;
    notifyListeners();
    try {
      recovery = await api.latestRecovery(id);
      recoveryError = null;
    } on BackendException catch (e) {
      recoveryError = e.message;
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
    final r = SessionRecorder(
      directory: await SessionStore.directory(),
      sessionId: const Uuid().v4(),
      setup: SessionSetup(
        sport: sport,
        sessionType: sessionType,
        placement: placement,
        athleteId: settings.athleteId,
        notes: notes,
      ),
      appVersion: appVersion,
      deviceModel: _deviceModel,
    );
    await r.start();
    recorder = r;
    await WakelockPlus.enable();
    notifyListeners();
  }

  Future<void> stopSession() async {
    final r = recorder;
    if (r == null) return;
    await r.stop();
    await WakelockPlus.disable();
    notes = '';
    await refreshSessions();
    notifyListeners();
  }

  void markEvent(String label) {
    recorder?.markEvent(label);
    notifyListeners();
  }

  // ---- sessions list --------------------------------------------------------

  Future<void> refreshSessions() async {
    sessions = await SessionStore.list();
    final done = settings.uploadedSessionIds;
    for (final s in sessions) {
      if (done.contains(s.id)) uploadStatus[s.id] = 'Uploaded';
    }
    notifyListeners();
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
    motionSource.stop();
    hr.removeListener(notifyListeners);
    hr.dispose();
    super.dispose();
  }
}
