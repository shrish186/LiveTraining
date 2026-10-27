import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

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

  /// True for sessions recorded by the Apple Watch app and received from the watch.
  bool get fromWatch =>
      (metadata['sources'] as List? ?? const []).any((s) => s is Map && s['id'] == 'apple_watch');
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
}
