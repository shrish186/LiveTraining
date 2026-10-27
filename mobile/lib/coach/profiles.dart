/// Sport profiles for live calls. Same rules as analysis/ltlib/profiles.py: every profile is
/// deep-merged over `general`, and `placements.<name>` overrides the `effort` block.
/// Source of truth: profiles/sport_profiles.yaml (bundled as assets/sport_profiles.yaml).
library;

import 'package:yaml/yaml.dart';

const baseProfile = 'general';

/// Converts YAML maps/lists into plain Dart maps/lists.
Object? _plain(Object? node) {
  if (node is YamlMap) return {for (final e in node.entries) e.key.toString(): _plain(e.value)};
  if (node is YamlList) return [for (final v in node) _plain(v)];
  return node;
}

Map<String, dynamic> deepMerge(Map<String, dynamic> base, Map<String, dynamic> override) {
  final out = Map<String, dynamic>.of(base);
  override.forEach((key, value) {
    final current = out[key];
    out[key] = value is Map<String, dynamic> && current is Map<String, dynamic> ? deepMerge(current, value) : value;
  });
  return out;
}

class SportProfiles {
  SportProfiles._(this._profiles);

  factory SportProfiles.parse(String yamlText) {
    final raw = (_plain(loadYaml(yamlText)) as Map<String, dynamic>)['profiles'] as Map<String, dynamic>;
    final base = raw[baseProfile] as Map<String, dynamic>;
    return SportProfiles._({
      for (final e in raw.entries)
        e.key: (e.key == baseProfile ? base : deepMerge(base, (e.value as Map<String, dynamic>?) ?? {}))
          ..['name'] = e.key,
    });
  }

  final Map<String, Map<String, dynamic>> _profiles;

  Iterable<String> get names => _profiles.keys;

  /// The profile for [sport], or `general` when no profile has that name.
  Map<String, dynamic> forSport(String? sport) => _profiles[sport] ?? _profiles[baseProfile]!;
}

double _num(Map<String, dynamic> m, String key) => (m[key] as num).toDouble();

/// Every number the live coach needs, read from one profile and one placement.
class CoachConfig {
  const CoachConfig({
    required this.profileName,
    required this.smoothingWindowS,
    required this.effortThreshold,
    required this.minEffortS,
    required this.mergeGapS,
    required this.baselineWindowS,
    required this.peakDropPct,
    required this.hrRecoveryWindowS,
    required this.warmupMinS,
    required this.warmupHrAboveRest,
    required this.warmupSustainS,
    required this.readinessLowBelow,
    required this.readinessHighFrom,
  });

  factory CoachConfig.fromProfile(Map<String, dynamic> profile, String? placement) {
    final effort = Map<String, dynamic>.of(profile['effort'] as Map<String, dynamic>);
    final override = (profile['placements'] as Map<String, dynamic>?)?[placement];
    if (override is Map<String, dynamic>) effort.addAll(override);
    final fatigue = profile['fatigue'] as Map<String, dynamic>;
    final warmup = profile['warmup'] as Map<String, dynamic>;
    final readiness = profile['readiness'] as Map<String, dynamic>;
    return CoachConfig(
      profileName: profile['name'] as String,
      smoothingWindowS: _num(profile['motion'] as Map<String, dynamic>, 'smoothing_window_s'),
      effortThreshold: _num(effort, 'threshold'),
      minEffortS: _num(effort, 'min_duration_s'),
      mergeGapS: effort['merge_gap_s'] == null ? 0 : _num(effort, 'merge_gap_s'),
      baselineWindowS: _num(fatigue, 'baseline_window_min') * 60,
      peakDropPct: _num(fatigue, 'peak_drop_pct'),
      hrRecoveryWindowS: _num(fatigue, 'hr_recovery_window_s'),
      warmupMinS: _num(warmup, 'min_minutes') * 60,
      warmupHrAboveRest: _num(warmup, 'hr_above_rest_bpm'),
      warmupSustainS: _num(warmup, 'sustain_s'),
      readinessLowBelow: _num(readiness, 'low_below'),
      readinessHighFrom: _num(readiness, 'high_from'),
    );
  }

  final String profileName;
  final double smoothingWindowS;
  final double effortThreshold;
  final double minEffortS;
  final double mergeGapS;
  final double baselineWindowS;
  final double peakDropPct;
  final double hrRecoveryWindowS;
  final double warmupMinS;
  final double warmupHrAboveRest;
  final double warmupSustainS;
  final double readinessLowBelow;
  final double readinessHighFrom;
}
