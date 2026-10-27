"""Sport-agnostic session analysis. Every threshold comes in as a parameter (from a sport profile)."""

from dataclasses import dataclass, field

import numpy as np
import pandas as pd

GRAVITY = 9.81
GRID_HZ = 10  # motion is binned to this rate before smoothing and detection


@dataclass
class Effort:
    start_s: float
    end_s: float
    peak: float
    hr_recovery_bpm: float | None = None  # HR at effort end minus HR `window` seconds later
    peak_drop_pct: float | None = None    # vs early-session baseline (positive = lower than baseline)
    fatigue: bool = False
    notes: list[str] = field(default_factory=list)

    @property
    def duration_s(self) -> float:
        return self.end_s - self.start_s


def dynamic_magnitude(x: np.ndarray, y: np.ndarray, z: np.ndarray) -> np.ndarray:
    """| |acc| - g |: ~0 when still, whatever the sensor orientation."""
    return np.abs(np.sqrt(x * x + y * y + z * z) - GRAVITY)


def smooth_on_grid(t_s: np.ndarray, values: np.ndarray, window_s: float) -> pd.Series:
    """Bins samples to GRID_HZ, fills short gaps, applies a centred rolling mean. Index = seconds."""
    if len(t_s) == 0:
        return pd.Series(dtype=float)
    bins = np.floor(t_s * GRID_HZ).astype(int)
    binned = pd.Series(values).groupby(bins).mean()
    grid = binned.reindex(np.arange(bins.min(), bins.max() + 1)).interpolate(limit=GRID_HZ, limit_area="inside")
    window = max(1, int(round(window_s * GRID_HZ)))
    smoothed = grid.rolling(window, center=True, min_periods=1).mean()
    smoothed.index = smoothed.index / GRID_HZ
    return smoothed


def detect_efforts(mag: pd.Series, threshold: float, min_duration_s: float, merge_gap_s: float = 0.0) -> list[Effort]:
    """Runs where the smoothed magnitude is above `threshold`. Runs closer than `merge_gap_s` are merged.
    Runs shorter than `min_duration_s` are dropped."""
    if mag.empty:
        return []
    t = mag.index.to_numpy(dtype=float)
    above = (mag.to_numpy() > threshold).astype(int)
    edges = np.diff(np.concatenate([[0], above, [0]]))
    starts, ends = np.flatnonzero(edges == 1), np.flatnonzero(edges == -1) - 1
    runs: list[list[int]] = []
    for s, e in zip(starts, ends):
        if runs and t[s] - t[runs[-1][1]] <= merge_gap_s:
            runs[-1][1] = e
        else:
            runs.append([s, e])
    step = 1.0 / GRID_HZ
    efforts = []
    for s, e in runs:
        start, end = t[s], t[e] + step
        if end - start >= min_duration_s:
            efforts.append(Effort(start_s=float(start), end_s=float(end), peak=float(mag.iloc[s:e + 1].max())))
    return efforts


def hr_at(hr_t: np.ndarray, hr_v: np.ndarray, t: float, max_gap_s: float = 5.0) -> float | None:
    """HR interpolated at time t, or None if there is no HR sample within max_gap_s."""
    if len(hr_t) == 0 or np.min(np.abs(hr_t - t)) > max_gap_s:
        return None
    return float(np.interp(t, hr_t, hr_v))


def add_hr_recovery(efforts: list[Effort], hr_t: np.ndarray, hr_v: np.ndarray, window_s: float) -> None:
    """Sets hr_recovery_bpm on each effort, unless the next effort starts within the window."""
    for i, effort in enumerate(efforts):
        later = effort.end_s + window_s
        if i + 1 < len(efforts) and efforts[i + 1].start_s < later:
            effort.notes.append("next effort inside recovery window")
            continue
        at_end, after = hr_at(hr_t, hr_v, effort.end_s), hr_at(hr_t, hr_v, later)
        if at_end is None or after is None:
            effort.notes.append("no HR coverage")
            continue
        effort.hr_recovery_bpm = at_end - after


@dataclass
class FatigueResult:
    baseline_peak: float | None
    baseline_hr_recovery: float | None
    first_flagged: Effort | None


def assess_fatigue(efforts: list[Effort], baseline_window_s: float, peak_drop_pct: float) -> FatigueResult:
    """Flags "fatigue building" on an effort after the baseline window when BOTH:
    - its peak is >= peak_drop_pct below the mean peak of efforts in the baseline window, AND
    - its HR recovery is slower (smaller drop) than the mean baseline HR recovery.
    """
    baseline = [e for e in efforts if e.start_s < baseline_window_s]
    if not baseline:
        return FatigueResult(None, None, None)
    base_peak = float(np.mean([e.peak for e in baseline]))
    base_hrr_values = [e.hr_recovery_bpm for e in baseline if e.hr_recovery_bpm is not None]
    base_hrr = float(np.mean(base_hrr_values)) if base_hrr_values else None
    first = None
    for e in efforts:
        if e.start_s < baseline_window_s:
            continue
        e.peak_drop_pct = (base_peak - e.peak) / base_peak * 100.0
        slower = base_hrr is not None and e.hr_recovery_bpm is not None and e.hr_recovery_bpm < base_hrr
        e.fatigue = e.peak_drop_pct >= peak_drop_pct and slower
        if e.fatigue and first is None:
            first = e
    return FatigueResult(base_peak, base_hrr, first)


def motion_load(mag: pd.Series) -> float:
    """Integral of smoothed dynamic magnitude over time, in (m/s²)·min. A simple, sport-agnostic load number."""
    return float(mag.sum() / GRID_HZ / 60.0) if not mag.empty else 0.0
