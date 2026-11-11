"""Repeated big actions at the end of a run-up, from a leg-worn sensor: one landing spike much harder
than the strides before it. The profile's `actions` block names them and sets the thresholds (in
cricket: a delivery's front-foot contact; a jump shot or a javelin plant would look the same).

Sport-agnostic: everything comes in as parameters. Works on the footstrikes of `steps.detect_strikes`,
so the same total-|acc|-in-g convention applies.
"""

from dataclasses import dataclass

import numpy as np

from .steps import Strike


@dataclass
class Action:
    t_s: float
    peak_g: float               # the landing spike
    runup_strikes: int          # sensor-leg strikes in the run-up window before it
    runup_peak_g: float         # median strike peak in the run-up
    runup_stride_ms: float | None  # median time between run-up strikes (shorter = faster run-up)


def detect_actions(strikes: list[Strike], min_peak_g: float, min_ratio: float, runup_window_s: float,
                   min_runup_strikes: int, min_gap_s: float, max_stride_s: float) -> list[Action]:
    """A strike counts as an action when it is at least `min_peak_g`, at least `min_ratio` times the
    median of the run-up strikes in the `runup_window_s` before it, and there are `min_runup_strikes`
    of those. Of candidates closer than `min_gap_s`, the hardest wins (a follow-through stride or a
    second big step is not a second action)."""
    times = np.array([s.t_s for s in strikes])
    candidates: list[Action] = []
    for i, s in enumerate(strikes):
        if s.peak_g < min_peak_g:
            continue
        before = [p for p, t in zip(strikes[:i], times[:i]) if s.t_s - runup_window_s <= t < s.t_s]
        if len(before) < min_runup_strikes:
            continue
        runup_peak = float(np.median([p.peak_g for p in before]))
        if s.peak_g < min_ratio * runup_peak:
            continue
        gaps = np.diff([p.t_s for p in before])
        gaps = gaps[gaps <= max_stride_s]
        candidates.append(Action(s.t_s, s.peak_g, len(before), runup_peak,
                                 float(np.median(gaps) * 1000) if len(gaps) else None))
    kept: list[Action] = []
    for a in sorted(candidates, key=lambda a: -a.peak_g):
        if all(abs(a.t_s - k.t_s) >= min_gap_s for k in kept):
            kept.append(a)
    return sorted(kept, key=lambda a: a.t_s)


@dataclass
class ActionDrift:
    compared: int
    peak_g_pct: float | None        # landing spike, last n vs first n, %
    runup_stride_ms: float | None   # run-up stride time change, ms (+ = slower run-up)


def action_drift(actions: list[Action], n: int) -> ActionDrift | None:
    """The last `n` actions against the first `n`: a softer landing or a slower run-up late in a
    spell is the fatigue sign. None if there are fewer than 2n actions."""
    if n < 1 or len(actions) < 2 * n:
        return None
    first, last = actions[:n], actions[-n:]
    p0, p1 = np.mean([a.peak_g for a in first]), np.mean([a.peak_g for a in last])
    s0 = [a.runup_stride_ms for a in first if a.runup_stride_ms is not None]
    s1 = [a.runup_stride_ms for a in last if a.runup_stride_ms is not None]
    return ActionDrift(n, float((p1 - p0) / p0 * 100),
                       float(np.mean(s1) - np.mean(s0)) if s0 and s1 else None)
