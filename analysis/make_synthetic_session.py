"""Generate a realistic fake session in the session format, for testing without hardware.

Timeline (default, ~31 min):
  0:00-1:00  standing, sync jumps at 0:20
  1:00-10:00 warm-up jog
  then 6 hard 25 s efforts with walking rests. The last efforts are a bit weaker
  and HR recovers more slowly, so the analysis should flag "fatigue building".

Usage: python make_synthetic_session.py [--out output/] [--rate 100] [--sport soccer] [--seed 7]
"""

import argparse
import json
import math
import uuid
from datetime import UTC, datetime
from pathlib import Path

import numpy as np

from ltlib.session_io import HEADER, format_float

# Effort start times (s), relative intensity, HR recovery time constant (s; bigger = slower).
# The first three fall inside the 15-minute baseline window.
EFFORTS = [(630, 1.00, 45), (780, 1.00, 45), (870, 0.99, 47),
           (1200, 0.96, 60), (1440, 0.84, 80), (1680, 0.78, 95)]
EFFORT_S = 25
SESSION_S = 1860

# Per activity: vertical oscillation amplitude (m/s²), step frequency (Hz), HR target (bpm)
ACTIVITY = {"still": (0.0, 0.0, 70), "walk": (1.5, 1.8, 95), "jog": (4.2, 2.7, 138), "sprint": (13.0, 3.8, 182)}


def activity_at(t: float) -> tuple[str, float, float]:
    """(activity, intensity scale, HR recovery tau) at time t."""
    for start, scale, tau in EFFORTS:
        if start <= t < start + EFFORT_S:
            return "sprint", scale, tau
    last_tau = 45.0
    for start, _, tau in EFFORTS:
        if t >= start + EFFORT_S:
            last_tau = tau
    if t < 60:
        return "still", 1.0, 30.0
    if t < 600:
        return "jog", 1.0, 30.0
    return "walk", 1.0, last_tau


def generate(rate_hz: int = 100, seed: int = 7) -> tuple[list[str], dict]:
    rng = np.random.default_rng(seed)
    rows: list[str] = [",".join(HEADER)]

    def event(t_s: float, label: str) -> tuple[int, str]:
        return int(t_s * 1000), f"{int(t_s * 1000)},phone,event,,,,{label}"

    timed: list[tuple[int, str]] = [event(0, "session_start"), event(20, "sync_jumps"), event(600, "drill_start"),
                                    event(SESSION_S - 5, "drill_end"), event(SESSION_S - 0.01, "session_end")]

    # Motion at rate_hz, with timing jitter like real sensor batches.
    n = SESSION_S * rate_hz
    t = np.arange(n) / rate_hz + rng.normal(0, 0.0015, n).clip(-0.004, 0.004)
    t = np.clip(t, 0, None)
    phase = 0.0
    prev_t = 0.0
    for i in range(n):
        ti = float(t[i])
        name, scale, _ = activity_at(ti)
        amp, freq, _ = ACTIVITY[name]
        amp *= scale
        phase += 2 * math.pi * freq * max(ti - prev_t, 0)
        prev_t = ti
        vertical = amp * math.sin(phase)
        if 20 <= ti < 23:  # three sync jumps: sharp spikes
            k = (ti - 20) % 1.0
            vertical += 25.0 * math.exp(-((k - 0.5) ** 2) / 0.002)
        ax = 0.4 * amp * math.sin(phase / 2) + rng.normal(0, 0.15)
        ay = 9.81 + vertical + rng.normal(0, 0.15)
        az = 0.3 * amp * math.cos(phase) + rng.normal(0, 0.15)
        gx, gy, gz = 0.3 * amp * math.cos(phase / 2) / 9, rng.normal(0, 0.02), 0.2 * amp * math.sin(phase) / 9
        t_ms = int(round(ti * 1000))
        timed.append((t_ms, f"{t_ms},phone,acc,{format_float(ax)},{format_float(ay)},{format_float(az)},"))
        timed.append((t_ms, f"{t_ms},phone,gyro,{format_float(gx)},{format_float(gy)},{format_float(gz)},"))

    # HR at ~1 Hz: first-order response towards the activity's target. Rises fast, recovers with tau.
    hr = 68.0
    hr_t = 0.0
    while hr_t < SESSION_S:
        name, scale, tau = activity_at(hr_t)
        target = ACTIVITY[name][2] if name != "sprint" else 138 + (ACTIVITY["sprint"][2] - 138) * scale
        dt = 1.0
        rate_tau = 12.0 if target > hr else tau
        hr += (target - hr) * (1 - math.exp(-dt / rate_tau))
        bpm = int(round(hr + rng.normal(0, 0.8)))
        t_ms = int(hr_t * 1000)
        timed.append((t_ms, f"{t_ms},whoop_hr,hr,,,,{bpm}"))
        rr = 60000.0 / bpm + rng.normal(0, 8)
        timed.append((t_ms, f"{t_ms},whoop_hr,rr,,,,{format_float(rr)}"))
        hr_t += dt + rng.normal(0, 0.02)

    timed.sort(key=lambda r: r[0])
    rows.extend(r for _, r in timed)

    metadata = {
        "format_version": 1,
        "session_id": str(uuid.UUID(bytes=rng.bytes(16), version=4)),
        "athlete_id": None,
        "sport": "soccer",
        "session_type": "training",
        "started_at": datetime(2026, 10, 27, 18, 0, tzinfo=UTC).isoformat().replace("+00:00", "Z"),
        "app_version": "synthetic",
        "device_model": "synthetic",
        "sources": [{"id": "phone", "kinds": ["acc", "gyro"], "sample_rate_hz": rate_hz},
                    {"id": "whoop_hr", "kinds": ["hr", "rr"], "sample_rate_hz": 1}],
        "placement": "phone_armband",
        "notes": "synthetic: warm-up jog + 6 x 25 s hard efforts, fatigue in the last two",
    }
    return rows, metadata


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--out", default="output", help="output directory")
    parser.add_argument("--name", default="synthetic", help="basename for .csv and .json")
    parser.add_argument("--rate", type=int, default=100, help="motion sample rate, Hz")
    parser.add_argument("--sport", default="soccer")
    parser.add_argument("--seed", type=int, default=7)
    args = parser.parse_args()

    rows, metadata = generate(args.rate, args.seed)
    metadata["sport"] = args.sport
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    csv_path, json_path = out / f"{args.name}.csv", out / f"{args.name}.json"
    csv_path.write_text("\n".join(rows) + "\n")
    json_path.write_text(json.dumps(metadata, indent=2) + "\n")
    print(f"wrote {csv_path} ({len(rows) - 1} rows) and {json_path}")


if __name__ == "__main__":
    main()
