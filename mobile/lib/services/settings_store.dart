import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';

class SettingsStore {
  SettingsStore(this._prefs);

  static Future<SettingsStore> load() async => SettingsStore(await SharedPreferences.getInstance());

  final SharedPreferences _prefs;

  String get backendUrl => _prefs.getString('backend_url') ?? defaultBackendUrl;
  set backendUrl(String v) => _prefs.setString('backend_url', v.trim().replaceFirst(RegExp(r'/+$'), ''));

  int? get athleteId => _prefs.getInt('athlete_id');
  set athleteId(int? v) => v == null ? _prefs.remove('athlete_id') : _prefs.setInt('athlete_id', v);

  String get sport => _prefs.getString('sport') ?? 'general';
  set sport(String v) => _prefs.setString('sport', v);

  String get sessionType => _prefs.getString('session_type') ?? 'training';
  set sessionType(String v) => _prefs.setString('session_type', v);

  String get placement => _prefs.getString('placement') ?? 'phone_armband';
  set placement(String v) => _prefs.setString('placement', v);

  Set<String> get uploadedSessionIds => (_prefs.getStringList('uploaded_sessions') ?? const []).toSet();
  void markUploaded(String id) => _prefs.setStringList('uploaded_sessions', {...uploadedSessionIds, id}.toList());
}
