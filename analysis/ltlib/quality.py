"""Data quality: is a recording good enough to trust the numbers that come out of it?

Checks one motion stream for the things that silently ruin metrics: lost samples, dropouts, a
sensor that hit its range (clipping), a sensor that reads gravity wrongly (calibration) and a
strap that moved during the session. Also the building blocks for our own sensor: fusing a low-g
and a high-g accelerometer into one unclipped signal, and mapping a sensor's clock onto the phone's.

Sport-agnostic: every threshold comes in as a parameter (the `quality` block of a sport profile).
"""

from dataclasses import dataclass, field

import numpy as np

from .core import GRAVITY


@dataclass
class StreamQuality:
    samples: int
    duration_s: float
    rate_hz: float               # samples in a typical (median) second
    lost_pct: float              # samples missing against that rate
    gaps: int                    # intervals longer than gap_ms
    longest_gap_s: float
    clipped_pct: float           # samples stuck at the sensor's limit
    clip_level_g: float | None   # the limit they are stuck at, if clipping was found
    gravity_error_pct: float | None  # |acc| at rest vs 1 g (None: never at rest)
    tilt_change_deg: float | None    # gravity direction, first rest vs last rest (strap moved?)
    score: int = 100
    grade: str = "good"          # good / fair / poor
    issues: list[str] = field(default_factory=list)


def _rest_windows(t: np.ndarray, acc: np.ndarray, still_std_g: float, window_s: float = 1.0) -> list[np.ndarray]:
    """Mean acceleration vector (m/s²) of each window where the sensor was still."""
    mag_g = np.linalg.norm(acc, axis=1) / GRAVITY
    out = []
    edges = np.arange(t[0], t[-1], window_s)
    idx = np.searchsorted(t, edges)
    for a, b in zip(idx[:-1], idx[1:]):
        if b - a >= 5 and float(np.std(mag_g[a:b])) <= still_std_g:
            out.append(acc[a:b].mean(axis=0))
    return out


def stream_quality(t_s: np.ndarray, x: np.ndarray, y: np.ndarray, z: np.ndarray, *, gap_ms: float,
                   clip_min_samples: int, still_std_g: float, gravity_tolerance_pct: float,
                   max_tilt_change_deg: float, max_lost_pct: float) -> StreamQuality | None:
    """Quality of one accelerometer stream (m/s², gravity included). None if there is too little data."""
    if len(t_s) < 20:
        return None
    order = np.argsort(t_s, kind="stable")
    t = np.asarray(t_s, dtype=float)[order]
    acc = np.column_stack([x, y, z]).astype(float)[order]
    duration = float(t[-1] - t[0])
    if duration <= 0:
        return None

    # Rate and loss: whole seconds only, against the typical second.
    per_second = np.bincount(np.floor(t - t[0]).astype(int))[: max(int(duration), 1)]
    rate = float(np.median(per_second))
    expected = rate * duration
    lost_pct = max(0.0, (1 - len(t) / expected) * 100) if expected else 0.0
    dt = np.diff(t)
    gaps = int((dt > gap_ms / 1000).sum())
    longest_gap = float(dt.max())

    # Clipping: real peaks are single samples; a sensor at its limit repeats the same top value.
    peak = float(np.abs(acc).max())
    at_limit = int((np.abs(acc) >= 0.995 * peak).any(axis=1).sum())
    clipping = at_limit >= clip_min_samples and peak > 1.5 * GRAVITY
    clipped_pct = at_limit / len(t) * 100 if clipping else 0.0

    rests = _rest_windows(t, acc, still_std_g)
    gravity_error = tilt = None
    if rests:
        norms = np.array([np.linalg.norm(r) for r in rests])
        gravity_error = float(abs(np.median(norms) / GRAVITY - 1) * 100)
        if len(rests) >= 2:
            a, b = rests[0] / np.linalg.norm(rests[0]), rests[-1] / np.linalg.norm(rests[-1])
            tilt = float(np.degrees(np.arccos(np.clip(a @ b, -1, 1))))

    q = StreamQuality(len(t), duration, rate, lost_pct, gaps, longest_gap, clipped_pct,
                      peak / GRAVITY if clipping else None, gravity_error, tilt)
    _grade(q, gravity_tolerance_pct, max_tilt_change_deg, max_lost_pct)
    return q


def _grade(q: StreamQuality, gravity_tolerance_pct: float, max_tilt_change_deg: float, max_lost_pct: float) -> None:
    penalty = 0.0
    if q.lost_pct > max_lost_pct:
        penalty += min(40, q.lost_pct * 4)
        q.issues.append(f"{q.lost_pct:.1f}% of samples missing")
    if q.gaps:
        penalty += min(30, 5 * q.gaps + 10 * max(0.0, q.longest_gap_s - 1))
        q.issues.append(f"{q.gaps} dropout{'s' if q.gaps != 1 else ''}, longest {q.longest_gap_s:.1f} s")
    if q.clip_level_g is not None:
        penalty += min(30, 10 + q.clipped_pct * 20)
        q.issues.append(f"sensor hit its limit ({q.clip_level_g:.0f} g): impact peaks read low")
    if q.gravity_error_pct is not None and q.gravity_error_pct > gravity_tolerance_pct:
        penalty += 15
        q.issues.append(f"reads gravity {q.gravity_error_pct:.0f}% off: needs calibration")
    if q.tilt_change_deg is not None and q.tilt_change_deg > max_tilt_change_deg:
        penalty += 15
        q.issues.append(f"sensor angle changed {q.tilt_change_deg:.0f}° between start and end: strap may have moved")
    q.score = int(round(max(0.0, 100 - penalty)))
    q.grade = "good" if q.score >= 85 else "fair" if q.score >= 60 else "poor"


def hr_coverage_pct(hr_t_s: np.ndarray, duration_s: float, max_gap_s: float = 5.0) -> float:
    """Share of the session with a heart-rate sample at most max_gap_s away."""
    if len(hr_t_s) == 0 or duration_s <= 0:
        return 0.0
    seconds = np.arange(0, duration_s, 1.0)
    t = np.sort(hr_t_s)
    i = np.clip(np.searchsorted(t, seconds), 1, len(t) - 1)
    nearest = np.minimum(np.abs(seconds - t[i - 1]), np.abs(seconds - t[i]))
    return float((nearest <= max_gap_s).mean() * 100)


def fuse_ranges(low: np.ndarray, high: np.ndarray, low_limit: float, blend_from: float) -> np.ndarray:
    """One unclipped signal from a precise low-range and a coarse high-range accelerometer sampled
    together (arrays of shape (n, 3), same units). Below `blend_from` the low range is used as is;
    from there to `low_limit` the two are blended; at the limit and above only the high range."""
    low, high = np.asarray(low, dtype=float), np.asarray(high, dtype=float)
    level = np.abs(low).max(axis=1, keepdims=True)
    w = np.clip((level - blend_from) / (low_limit - blend_from), 0.0, 1.0)
    return (1 - w) * low + w * high


def fit_clock(sensor_t: np.ndarray, received_t: np.ndarray) -> tuple[float, float]:
    """Maps a sensor's clock onto the receiver's: returns (scale, offset) with
    receiver_time ≈ scale * sensor_time + offset.

    Packets arrive late by a varying radio delay, never early, so the true line is the lower edge
    of the points: fit the slope by least squares, then shift it down to the fastest packets."""
    s, r = np.asarray(sensor_t, dtype=float), np.asarray(received_t, dtype=float)
    if len(s) < 2 or np.ptp(s) == 0:
        return 1.0, float(r[0] - s[0]) if len(s) else 0.0
    scale, offset = np.polyfit(s, r, 1)
    residual = r - (scale * s + offset)
    return float(scale), float(offset + np.percentile(residual, 2))
