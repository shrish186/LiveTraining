import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../sources/motion_source.dart';
import 'csv_row.dart';

/// What the athlete chose before pressing Start. Sport-agnostic: just strings.
class SessionSetup {
  const SessionSetup({
    required this.sport,
    required this.sessionType,
    required this.placement,
    this.athleteId,
    this.notes = '',
  });

  final String sport;
  final String sessionType;
  final String placement;
  final int? athleteId;
  final String notes;
}

/// Records every [Sample] it is given into `<dir>/<sessionId>.csv`, stamped with ONE monotonic
/// Stopwatch shared by all streams. Rows go to disk in small batches; nothing accumulates in memory.
///
/// The metadata JSON is written at start (so a killed app still leaves an uploadable session)
/// and rewritten on stop with the final duration and measured sample rates.
class SessionRecorder {
  SessionRecorder({
    required this.directory,
    required this.sessionId,
    required this.setup,
    required this.appVersion,
    required this.deviceModel,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  static const flushEveryRows = 500;

  final Directory directory;
  final String sessionId;
  final SessionSetup setup;
  final String appVersion;
  final String deviceModel;
  final DateTime Function() _clock;

  final Stopwatch _stopwatch = Stopwatch();
  final StringBuffer _buffer = StringBuffer();
  int _buffered = 0;
  IOSink? _sink;
  Timer? _flushTimer;
  late DateTime _startedAt;
  bool _stopped = false;

  /// Row counts per `source/kind`, e.g. `phone/acc`.
  final Map<String, int> counts = {};
  final List<String> events = [];

  File get csvFile => File('${directory.path}/$sessionId.csv');
  File get metadataFile => File('${directory.path}/$sessionId.json');
  Duration get elapsed => _stopwatch.elapsed;
  bool get isRecording => _sink != null && !_stopped;

  int count(String source, String kind) => counts['$source/$kind'] ?? 0;

  Future<void> start() async {
    await directory.create(recursive: true);
    _startedAt = _clock().toUtc();
    _sink = csvFile.openWrite();
    _sink!.writeln(csvHeader);
    _stopwatch.start();
    add(const Sample.event('phone', 'session_start'));
    await _writeMetadata();
    _flushTimer = Timer.periodic(const Duration(seconds: 1), (_) => _flush());
  }

  /// Stamps the sample with the shared Stopwatch and queues the CSV row.
  void add(Sample s) {
    if (!isRecording) return;
    final tMs = _stopwatch.elapsedMilliseconds;
    _buffer.writeln(csvRow(tMs, s));
    _buffered++;
    final key = '${s.source}/${s.kind}';
    counts[key] = (counts[key] ?? 0) + 1;
    if (s.kind == 'event') events.add(sanitizeLabel(s.label ?? ''));
    if (_buffered >= flushEveryRows) _flush();
  }

  void markEvent(String label) => add(Sample.event('phone', label));

  void _flush() {
    if (_buffered == 0 || _sink == null) return;
    _sink!.write(_buffer.toString());
    _buffer.clear();
    _buffered = 0;
  }

  Future<void> stop() async {
    if (!isRecording) return;
    add(const Sample.event('phone', 'session_end'));
    _stopped = true;
    _stopwatch.stop();
    _flushTimer?.cancel();
    _flush();
    await _sink!.flush();
    await _sink!.close();
    await _writeMetadata();
  }

  Map<String, dynamic> metadata() {
    final seconds = _stopwatch.elapsedMilliseconds / 1000.0;
    final bySource = <String, Map<String, int>>{};
    counts.forEach((key, n) {
      final [source, kind] = key.split('/');
      if (kind != 'event') (bySource[source] ??= {})[kind] = n;
    });
    return {
      'format_version': 1,
      'session_id': sessionId,
      'athlete_id': setup.athleteId,
      'sport': setup.sport,
      'session_type': setup.sessionType,
      // Millisecond precision: used to line this recording up with a watch recording.
      'started_at': '${_startedAt.toIso8601String().substring(0, 23)}Z',
      'app_version': appVersion,
      'device_model': deviceModel,
      'sources': [
        for (final entry in bySource.entries)
          {
            'id': entry.key,
            'kinds': entry.value.keys.toList()..sort(),
            // Measured average rate of the busiest stream of this source.
            'sample_rate_hz': seconds > 0
                ? double.parse((entry.value.values.reduce((a, b) => a > b ? a : b) / seconds).toStringAsFixed(1))
                : null,
          },
      ],
      'placement': setup.placement,
      'notes': setup.notes,
      'duration_ms': _stopwatch.elapsedMilliseconds,
      'complete': _stopped,
    };
  }

  Future<void> _writeMetadata() =>
      metadataFile.writeAsString(const JsonEncoder.withIndent('  ').convert(metadata()));
}
