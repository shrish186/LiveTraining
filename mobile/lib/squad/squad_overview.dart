/// The coach's view of a squad: per player, this week against their own usual week, how their last
/// session went, and what needs a look. Built from the players' saved session summaries only.
/// Pure Dart, unit-testable.
///
/// Wording rule: load, fatigue, readiness. Never an injury or medical claim.
library;

import '../coach/advice.dart';
import '../util/day_summary.dart';
import '../util/trends.dart';

class PlayerFlag {
  const PlayerFlag(this.level, this.text);

  final AdviceLevel level;
  final String text;
}

class PlayerOverview {
  PlayerOverview({
    required this.name,
    required this.entries,
    required this.trends,
    required this.flags,
    this.lastSession,
    this.lastHeldPct,
    this.lastStartPct,
  });

  final String name;

  /// All this player's sessions (for their own trends screen).
  final List<DayEntry> entries;
  final Trends trends;
  final List<PlayerFlag> flags;
  final DayEntry? lastSession;

  /// Last session: last few actions' landing as % of the first few (100 = held up).
  final double? lastHeldPct;

  /// Last session's first actions against the player's usual start, % (100 = usual).
  final double? lastStartPct;

  WeekTotals get thisWeek => trends.thisWeek;

  /// Mean of the earlier weeks (in the trends window) that had any of the player's actions.
  double? get usualWeeklyActions {
    final earlier = trends.weeks.take(trends.weeks.length - 1).map((w) => w.actions).where((a) => a > 0).toList();
    return earlier.isEmpty ? null : earlier.reduce((a, b) => a + b) / earlier.length;
  }

  double? get usualWeeklyLoad {
    final earlier = trends.weeks.take(trends.weeks.length - 1).map((w) => w.load).where((l) => l > 0).toList();
    return earlier.isEmpty ? null : earlier.reduce((a, b) => a + b) / earlier.length;
  }

  /// The most serious flag's level: warn > info > good.
  AdviceLevel get status => flags.any((f) => f.level == AdviceLevel.warn)
      ? AdviceLevel.warn
      : flags.any((f) => f.level == AdviceLevel.info)
      ? AdviceLevel.info
      : AdviceLevel.good;
}

/// Thresholds for the coach's flags; the defaults match the advice rules.
class OverviewRules {
  const OverviewRules({this.spikeRatio = 1.3, this.fadedBelowPct = 90, this.softStartPct = 8, this.minUsualActions = 6});

  final double spikeRatio;
  final double fadedBelowPct;
  final double softStartPct;
  final double minUsualActions;
}

/// One overview per player, players needing a look first. [sessions]: (player name, session) pairs.
List<PlayerOverview> squadOverview(
  Iterable<(String, DayEntry)> sessions,
  DateTime now, {
  OverviewRules rules = const OverviewRules(),
}) {
  final byPlayer = <String, List<DayEntry>>{};
  for (final (name, e) in sessions) {
    (byPlayer[name] ??= []).add(e);
  }
  final out = <PlayerOverview>[];
  byPlayer.forEach((name, entries) {
    entries.sort((a, b) => a.startedAt.compareTo(b.startedAt));
    final trends = Trends.of(entries, now);
    final last = entries.last;
    final first = last.summary?.firstActionG, lastG = last.summary?.lastActionG;
    final held = first != null && lastG != null && first > 0 ? lastG / first * 100 : null;
    final usualStart = actionBaseline(entries, last.sport, before: last.startedAt);
    final start = first != null && usualStart != null && usualStart > 0 ? first / usualStart * 100 : null;

    final o = PlayerOverview(
      name: name,
      entries: entries,
      trends: trends,
      flags: [],
      lastSession: last,
      lastHeldPct: held,
      lastStartPct: start,
    );
    final w = o.thisWeek;
    final label = trends.actionsLabel ?? 'actions';
    final usualActions = o.usualWeeklyActions;
    final usualLoad = o.usualWeeklyLoad;
    if (w.sessions == 0) {
      o.flags.add(const PlayerFlag(AdviceLevel.info, 'No sessions this week'));
    }
    if (usualActions != null && usualActions >= rules.minUsualActions && w.actions > usualActions * rules.spikeRatio) {
      o.flags.add(PlayerFlag(AdviceLevel.warn, '${w.actions} $label vs ~${usualActions.round()} usual'));
    } else if (usualLoad != null && w.load > usualLoad * rules.spikeRatio) {
      o.flags.add(PlayerFlag(AdviceLevel.warn, 'Load up ${((w.load / usualLoad - 1) * 100).round()}% on usual'));
    }
    if (held != null && held < rules.fadedBelowPct) {
      o.flags.add(PlayerFlag(AdviceLevel.warn, 'Faded ${(100 - held).round()}% in last session'));
    }
    if (start != null && start <= 100 - rules.softStartPct) {
      o.flags.add(PlayerFlag(AdviceLevel.warn, 'Soft start: ${(100 - start).round()}% below usual'));
    }
    if (w.fatigueEfforts >= 2) {
      o.flags.add(PlayerFlag(AdviceLevel.warn, 'Fatigue called ${w.fatigueEfforts} times this week'));
    }
    if (o.flags.isEmpty) o.flags.add(const PlayerFlag(AdviceLevel.good, 'On track'));
    out.add(o);
  });
  int rank(AdviceLevel l) => switch (l) {
    AdviceLevel.warn => 0,
    AdviceLevel.info => 1,
    AdviceLevel.good => 2,
  };
  out.sort((a, b) {
    final r = rank(a.status).compareTo(rank(b.status));
    return r != 0 ? r : a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  return out;
}
