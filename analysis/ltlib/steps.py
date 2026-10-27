"""Per-step metrics from a leg-worn accelerometer: footstrikes, peak g, stride timing, impact load,
jump height. Sport-agnostic: every threshold comes in as a parameter (from the `steps`, `impact`
and `jumps` blocks of a sport profile).

Accelerations here are the TOTAL magnitude |acc| in g (standing still = 1 g), not the
gravity-removed motion magnitude: impact is conventionally reported that way.
"""

from dataclasses import dataclass

import numpy as np

from .core import GRAVITY


@dataclass
class Strike:
    t_s: float
    peak_g: float


@dataclass
class Jump:
    takeoff_s: float
    landing_s: float
    landing_peak_g: float

    @property
    def flight_s(self) -> float:
        return self.landing_s - self.takeoff_s

    @property
    def height_cm(self) -> float:
        """Flight-time method: h = g t² / 8."""
        return GRAVITY * self.flight_s ** 2 / 8 * 100


def total_g(x: np.ndarray, y: np.ndarray, z: np.ndarray) -> np.ndarray:
    return np.sqrt(x * x + y * y + z * z) / GRAVITY


def detect_strikes(t_s: np.ndarray, g: np.ndarray, min_peak_g: float, min_interval_s: float) -> list[Strike]:
    """Footstrikes of the leg wearing the sensor: local maxima above `min_peak_g`, strongest first,
    none closer than `min_interval_s` to a stronger one. The other foot's landing also shows up on
    the sensor, smaller and between two of ours; the interval rule drops it."""
    if len(g) < 3:
        return []
    inner = np.arange(1, len(g) - 1)
    is_peak = (g[inner] >= g[inner - 1]) & (g[inner] >= g[inner + 1]) & (g[inner] > min_peak_g)
    candidates = inner[is_peak]
    kept: list[int] = []
    taken = np.array([], dtype=float)
    for i in candidates[np.argsort(-g[candidates], kind="stable")]:
        if taken.size and np.min(np.abs(taken - t_s[i])) < min_interval_s:
            continue
        kept.append(int(i))
        taken = np.append(taken, t_s[i])
    return [Strike(float(t_s[i]), float(g[i])) for i in sorted(kept)]


def stride_times(strikes: list[Strike], max_stride_s: float) -> np.ndarray:
    """Seconds between consecutive strikes of the same leg, keeping only those while moving."""
    if len(strikes) < 2:
        return np.array([])
    gaps = np.diff([s.t_s for s in strikes])
    return gaps[gaps <= max_stride_s]


def impact_load(strikes: list[Strike], exponent: float = 1.0) -> float:
    """Sum of per-strike peak g, each raised to `exponent` (>1 weights the big hits more)."""
    return float(sum(s.peak_g ** exponent for s in strikes))


def detect_jumps(t_s: np.ndarray, g: np.ndarray, takeoff_g: float, flight_below_g: float,
                 landing_above_g: float, landing_peak_g: float, min_flight_s: float, max_flight_s: float,
                 quiet_before_s: float, quiet_std_g: float) -> list[Jump]:
    """Standing jumps: quiet stance, a push-off peak, a low-g flight, a landing spike, quiet again.

    Takeoff = first sample below `flight_below_g` after the push-off peak; landing = first sample
    back above `landing_above_g`. The quiet-stance checks before and after keep running strides
    (which also have a flight phase) out."""
    jumps: list[Jump] = []
    n = len(g)
    i = 0
    while i < n:
        if g[i] < takeoff_g:
            i += 1
            continue
        # push-off peak: walk to the local top
        while i + 1 < n and g[i + 1] >= g[i]:
            i += 1
        push = i
        before = (t_s >= t_s[push] - quiet_before_s - 0.3) & (t_s < t_s[push] - 0.3)
        quiet = before.sum() >= 5 and float(np.std(g[before])) <= quiet_std_g
        j = push
        while j < n and g[j] >= flight_below_g and t_s[j] - t_s[push] < 0.3:
            j += 1
        if not quiet or j >= n or g[j] >= flight_below_g:
            i = push + 1
            continue
        k = j
        while k < n and g[k] <= landing_above_g and t_s[k] - t_s[j] <= max_flight_s:
            k += 1
        if k >= n or g[k] <= landing_above_g:
            i = push + 1
            continue
        flight = float(t_s[k] - t_s[j])
        after = (t_s >= t_s[k]) & (t_s <= t_s[k] + 0.15)
        peak = float(g[after].max())
        settle = (t_s >= t_s[k] + 0.4) & (t_s < t_s[k] + 0.4 + quiet_before_s)
        settled = settle.sum() >= 5 and float(np.std(g[settle])) <= 2 * quiet_std_g
        if min_flight_s <= flight <= max_flight_s and peak >= landing_peak_g and settled:
            jumps.append(Jump(float(t_s[j]), float(t_s[k]), peak))
            i = k + 1
        else:
            i = push + 1
    return jumps


@dataclass
class EffortSteps:
    strikes: int
    peak_g: float | None        # mean strike peak during the effort
    stride_ms: float | None     # median time between strikes of the sensor leg
    stride_cv_pct: float | None  # stride-to-stride variability


def effort_steps(strikes: list[Strike], start_s: float, end_s: float, max_stride_s: float) -> EffortSteps:
    inside = [s for s in strikes if start_s <= s.t_s <= end_s]
    gaps = stride_times(inside, max_stride_s)
    return EffortSteps(
        strikes=len(inside),
        peak_g=float(np.mean([s.peak_g for s in inside])) if inside else None,
        stride_ms=float(np.median(gaps) * 1000) if len(gaps) else None,
        stride_cv_pct=float(np.std(gaps) / np.mean(gaps) * 100) if len(gaps) > 1 else None,
    )


@dataclass
class Drift:
    compared: int               # efforts on each side
    peak_g_pct: float | None    # change in mean strike peak, %
    stride_ms: float | None     # change in stride time, ms (+ = slower)
    stride_cv_pts: float | None  # change in stride variability, percentage points


def form_drift(per_effort: list[EffortSteps], n: int) -> Drift | None:
    """The last `n` efforts against the first `n`. None if there are fewer than 2n efforts."""
    if n < 1 or len(per_effort) < 2 * n:
        return None

    def mean(items: list[EffortSteps], attr: str) -> float | None:
        values = [getattr(e, attr) for e in items if getattr(e, attr) is not None]
        return float(np.mean(values)) if values else None

    first, last = per_effort[:n], per_effort[-n:]
    p0, p1 = mean(first, "peak_g"), mean(last, "peak_g")
    s0, s1 = mean(first, "stride_ms"), mean(last, "stride_ms")
    c0, c1 = mean(first, "stride_cv_pct"), mean(last, "stride_cv_pct")
    return Drift(
        compared=n,
        peak_g_pct=(p1 - p0) / p0 * 100 if p0 and p1 is not None else None,
        stride_ms=s1 - s0 if s0 is not None and s1 is not None else None,
        stride_cv_pts=c1 - c0 if c0 is not None and c1 is not None else None,
    )
