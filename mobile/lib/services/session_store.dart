import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../util/day_summary.dart';

class LocalSession {
  LocalSession(this.id, this.csv, this.metadataFile, this.metadata);

  final String id;
  final File csv;
  final File metadataFile;
  final Map<String, dynamic> metadata;

  String get sport => metadata['sport'] as String? ?? '?';
  String get sessionType => metadata['session_type'] as String? ?? '';
  DateTime? get startedAt => DateTime.tryParse(metadata['started_at'] as String? ?? '')?.toLocal();
  Duration get duration => Duration(milliseconds: (metadata['duration_ms'] as num?)?.toInt() ?? 0);
  bool get complete => metadata['complete'] as bool? ?? true;

  /// Set for sessions recorded in a squad session: whose leg the sensor was on.
  String? get player => metadata['player'] as String?;

  SessionSummary? get summary => SessionSummary.fromJson(metadata['summary']);

  DayEntry? get dayEntry {
    final t = startedAt;
    // A squad session is someone else's training, not the phone owner's day.
    return t == null || player != null
        ? null
        : DayEntry(startedAt: t, duration: duration, sport: sport, summary: summary);
  }

  /// This session as a day entry whoever it was for (squad sessions included), for the coach's overview.
  DayEntry? get anyEntry {
    final t = startedAt;
    return t == null ? null : DayEntry(startedAt: t, duration: duration, sport: sport, summary: summary);
  }

  /// True for sessions recorded by the Apple Watch app and received from the watch.
  /// True for sessions with data from our leg sensor.
  bool get fromSensor => (metadata['sources'] as List? ?? const []).any((s) => s is Map && s['id'] == 'xiao');

  bool get fromWatch => (metadata['sources'] as List? ?? const []).any((s) => s is Map && s['id'] == 'apple_watch');
}

/// Sessions recorded on this device, in `<app documents>/sessions/`.
class SessionStore {
  static Future<Directory> directory() async =>
      Directory('${(await getApplicationDocumentsDirectory()).path}/sessions');

  static Future<List<LocalSession>> list() async {
    final dir = await directory();
    if (!await dir.exists()) return [];
    final sessions = <LocalSession>[];
    await for (final f in dir.list()) {
      if (f is! File || !f.path.endsWith('.json')) continue;
      final csv = File(f.path.replaceFirst(RegExp(r'\.json$'), '.csv'));
      if (!await csv.exists()) continue;
      try {
        final meta = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        sessions.add(LocalSession(meta['session_id'] as String, csv, f, meta));
      } on FormatException {
        continue;
      }
    }
    sessions.sort((a, b) => (b.startedAt ?? DateTime(0)).compareTo(a.startedAt ?? DateTime(0)));
    return sessions;
  }

  /// Removes a session's CSV and metadata from the phone (not from a server it was uploaded to).
  static Future<void> delete(LocalSession s) async {
    for (final f in [s.csv, s.metadataFile]) {
      if (await f.exists()) await f.delete();
    }
  }
}
