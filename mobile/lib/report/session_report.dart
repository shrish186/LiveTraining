/// Everything the session report screen shows, computed from a recorded session file by replaying
/// it through the live coach (the same logic as during the session, parity-tested against the
/// Python analysis). Pure Dart: runs in a background isolate.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import '../coach/live_coach.dart';
import '../coach/profiles.dart';
import 'signal_quality.dart';

class _Row {
  _Row(this.index, this.tMs, this.source, this.kind, this.x, this.y, this.z, this.value);
  final int index;
  final int tMs;
  final String source;
  final String kind;
  final double x, y, z;
  final String value;
}

class ReportEvent {
  const ReportEvent(this.tS, this.label);
  final double tS;
  final String label;
}

class SessionReport {
  SessionReport({
    required this.durationS,
    required this.profileName,
    required this.placement,
    required this.motionSource,
    required this.efforts,
    required this.events,
    required this.bucketS,
    required this.motion,
    required this.hr,
    required this.load,
    required this.effortThreshold,
    this.hrAvg,
    this.hrMax,
    this.strikes,
    this.impactLoad,
    this.hardestG,
    this.quality,
    this.hrCoveragePct = 0,
  });

  final double durationS;
  final String profileName;
  final String? placement;

  /// The motion stream that was analysed: a body-worn sensor when there is one, else the phone.
  final String? motionSource;
  final List<LiveEffort> efforts;

  /// The athlete's own marks (not the coach's calls).
  final List<ReportEvent> events;

  /// Chart series, one value per [bucketS] seconds: peak smoothed motion (m/s²) and mean heart rate.
  final double bucketS;
  final List<double?> motion;
  final List<double?> hr;

  /// Motion load, (m/s²)·min.
  final double load;
  final double effortThreshold;
  final double? hrAvg;
  final double? hrMax;
  final int? strikes;
  final double? impactLoad;
  final double? hardestG;
  final StreamQuality? quality;
  final double hrCoveragePct;

  int get fatigueEfforts => efforts.where((e) => e.fatigue).length;

  static const _maxPoints = 400;
  static const _tickMs = 200;

  static SessionReport fromFiles(String csvPath, String metadataPath, String profilesYaml) {
    final meta = jsonDecode(File(metadataPath).readAsStringSync()) as Map<String, dynamic>;
    return build(File(csvPath).readAsLinesSync(), meta, SportProfiles.parse(profilesYaml));
  }

  static SessionReport build(List<String> csvLines, Map<String, dynamic> meta, SportProfiles profiles) {
    final rows = <_Row>[];
    for (var i = 1; i < csvLines.length; i++) {
      final f = csvLines[i].split(',');
      if (f.length != 7) continue;
      final t = int.tryParse(f[0]);
      if (t == null) continue;
      rows.add(
        _Row(
          i,
          t,
          f[1],
          f[2],
          double.tryParse(f[3]) ?? 0,
          double.tryParse(f[4]) ?? 0,
          double.tryParse(f[5]) ?? 0,
          f[6],
        ),
      );
    }
    // Batched sensors write slightly out of order: sort by time, file order breaking ties.
    rows.sort((a, b) => a.tMs != b.tMs ? a.tMs.compareTo(b.tMs) : a.index.compareTo(b.index));

    final accSources = {
      for (final r in rows)
        if (r.kind == 'acc') r.source,
    };
    final motionSource = accSources.isEmpty
        ? null
        : accSources.firstWhere((s) => s != 'phone', orElse: () => accSources.first);
    final hrSources = {
      for (final r in rows)
        if (r.kind == 'hr') r.source,
    };
    final hrSource = hrSources.contains('whoop_hr') ? 'whoop_hr' : (hrSources.isEmpty ? null : hrSources.first);

    final placement = meta['placement'] as String?;
    final profile = profiles.forSport(meta['sport'] as String?);
    final cfg = CoachConfig.fromProfile(profile, placement);
    final coach = LiveCoach(cfg);

    final durationMs = rows.isEmpty ? 0 : rows.last.tMs;
    final durationS = durationMs / 1000;
    final bucketS = math.max(1.0, (durationS / _maxPoints).ceilToDouble());
    final buckets = math.max(1, (durationS / bucketS).ceil());
    final motion = List<double?>.filled(buckets, null);
    final hrSum = List<double>.filled(buckets, 0);
    final hrCount = List<int>.filled(buckets, 0);
    int bucketOf(double tS) => math.min(buckets - 1, (tS / bucketS).floor());

    final events = <ReportEvent>[];
    final at = <double>[], ax = <double>[], ay = <double>[], az = <double>[];
    final hrTimes = <double>[];
    var hrTotal = 0.0;
    double? hrMax;
    var load = 0.0;
    var nextTick = 0;

    void tick(int tMs) {
      coach.tick(tMs);
      if (at.isEmpty) return;
      final b = bucketOf(tMs / 1000);
      motion[b] = math.max(motion[b] ?? 0, coach.smoothed);
      load += coach.smoothed * (_tickMs / 1000) / 60;
    }

    for (final r in rows) {
      while (nextTick <= r.tMs) {
        tick(nextTick);
        nextTick += _tickMs;
      }
      final tS = r.tMs / 1000;
      if (r.kind == 'acc' && r.source == motionSource) {
        coach.addAcc(r.tMs, r.x, r.y, r.z);
        at.add(tS);
        ax.add(r.x);
        ay.add(r.y);
        az.add(r.z);
      } else if (r.kind == 'hr' && r.source == hrSource) {
        final bpm = double.tryParse(r.value);
        if (bpm == null) continue;
        coach.addHr(r.tMs, bpm);
        hrTimes.add(tS);
        hrTotal += bpm;
        hrMax = math.max(hrMax ?? bpm, bpm);
        final b = bucketOf(tS);
        hrSum[b] += bpm;
        hrCount[b]++;
      } else if (r.kind == 'event' && !r.value.startsWith('call_') && !r.value.startsWith('session_')) {
        events.add(ReportEvent(tS, r.value));
      }
    }
    coach.tick(nextTick + 120000); // let the last heart-rate recovery window finish

    // Heart-rate coverage: seconds with a sample at most 5 s away.
    var covered = 0;
    var j = 0;
    final wholeSeconds = durationS.floor();
    for (var s = 0; s < wholeSeconds; s++) {
      while (j + 1 < hrTimes.length && (hrTimes[j + 1] - s).abs() <= (hrTimes[j] - s).abs()) {
        j++;
      }
      if (hrTimes.isNotEmpty && (hrTimes[j] - s).abs() <= 5) covered++;
    }

    return SessionReport(
      durationS: durationS,
      profileName: cfg.profileName,
      placement: placement,
      motionSource: motionSource,
      efforts: coach.efforts,
      events: events,
      bucketS: bucketS,
      motion: motion,
      hr: [for (var i = 0; i < buckets; i++) hrCount[i] == 0 ? null : hrSum[i] / hrCount[i]],
      load: load,
      effortThreshold: cfg.effortThreshold,
      hrAvg: hrTimes.isEmpty ? null : hrTotal / hrTimes.length,
      hrMax: hrMax,
      strikes: coach.strikes?.strikes,
      impactLoad: coach.strikes?.impactLoad,
      hardestG: coach.strikes?.hardestG,
      quality: streamQuality(at, ax, ay, az, QualityConfig.fromProfile(profile)),
      hrCoveragePct: wholeSeconds == 0 ? 0 : covered / wholeSeconds * 100,
    );
  }
}
