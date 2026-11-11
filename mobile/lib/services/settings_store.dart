import 'package:shared_preferences/shared_preferences.dart';

class SettingsStore {
  SettingsStore(this._prefs);

  static Future<SettingsStore> load() async => SettingsStore(await SharedPreferences.getInstance());

  final SharedPreferences _prefs;

  String get backendUrl => _prefs.getString('backend_url') ?? '';
  set backendUrl(String v) => _prefs.setString('backend_url', v.trim().replaceFirst(RegExp(r'/+$'), ''));

  int? get athleteId => _prefs.getInt('athlete_id');
  set athleteId(int? v) => v == null ? _prefs.remove('athlete_id') : _prefs.setInt('athlete_id', v);

  String get sport => _prefs.getString('sport') ?? 'general';
  set sport(String v) => _prefs.setString('sport', v);

  String get sessionType => _prefs.getString('session_type') ?? 'training';
  set sessionType(String v) => _prefs.setString('session_type', v);

  String get placement => _prefs.getString('placement') ?? 'phone_armband';
  set placement(String v) => _prefs.setString('placement', v);

  /// The leg sensor this phone reconnects to on start (single-athlete mode on the Live tab).
  String? get sensorId => _prefs.getString('sensor_id');
  String? get sensorName => _prefs.getString('sensor_name');
  void rememberSensor(String? id, String? name) {
    if (id == null) {
      _prefs.remove('sensor_id');
      _prefs.remove('sensor_name');
    } else {
      _prefs.setString('sensor_id', id);
      _prefs.setString('sensor_name', name ?? 'Sensor');
    }
  }

  /// Daily readiness checks (JSON list, see readiness/jump_test.dart).
  String? get jumpTests => _prefs.getString('jump_tests');
  set jumpTests(String? v) => v == null ? _prefs.remove('jump_tests') : _prefs.setString('jump_tests', v);

  /// Player names for squad sessions (one phone, several sensors).
  List<String> get squadPlayers => _prefs.getStringList('squad_players') ?? const [];
  set squadPlayers(List<String> v) => _prefs.setStringList('squad_players', v);

  Set<String> get uploadedSessionIds => (_prefs.getStringList('uploaded_sessions') ?? const []).toSet();
  void markUploaded(String id) => _prefs.setStringList('uploaded_sessions', {...uploadedSessionIds, id}.toList());
}
