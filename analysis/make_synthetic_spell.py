"""Generate a fake fast-bowling session from our leg sensor (ankle of the front leg), for demos and for
testing the delivery pipeline without a bowler.

Timeline (default, ~24 min): 5 min jog warm-up, then 3 overs (18 deliveries) about 40 s apart. Each delivery is
a run-up of strides speeding up, a hard front-foot landing, two follow-through strides and a walk back to the
mark. The last over lands softer and the run-up gets slower, so the analysis should show the drift. With
--marks the coach's Mark taps (1.5 s after each ball) are in the file too, for validate_session.py.

Usage: python make_synthetic_spell.py [--out output/] [--name spell] [--overs 3] [--marks] [--seed 3]
"""

import argparse
import json
import uuid
from datetime import UTC, datetime
from pathlib import Path

import numpy as np

from ltlib.session_io import HEADER, format_float

RATE_HZ = 104          # our sensor's rate
G = 9.81
WARMUP_S = 300
BALL_EVERY_S = 40
RUNUP_STRIDES = 12


def generate(overs: int = 3, marks: bool = False, seed: int = 3,
             warmup_s: float = WARMUP_S) -> tuple[list[str], dict, list[float]]:
    """Rows of the session CSV, its metadata, and the delivery times (s)."""
    rng = np.random.default_rng(seed)
    balls = overs * 6
    duration = warmup_s + 30 + balls * BALL_EVERY_S + 30
    t = np.arange(int(duration * RATE_HZ)) / RATE_HZ
    g = np.ones_like(t)

    def strike(at: float, peak: float, width: float = 0.012) -> None:
        i0, i1 = np.searchsorted(t, [at - 0.08, at + 0.08])
        g[i0:i1] += (peak - 1) * np.exp(-((t[i0:i1] - at) / width) ** 2)

    # Warm-up jog: our leg every 0.75 s, ~5 g.
    for at in np.arange(10, warmup_s, 0.75):
        strike(at + rng.normal(0, 0.01), 5.0 + rng.normal(0, 0.4))

    deliveries: list[float] = []
    hr_load: list[tuple[float, float]] = []   # (time, extra bpm) after each ball
    for k in range(balls):
        late = k >= balls - 6                  # the last over: softer landings, slower run-up
        start = warmup_s + 30 + k * BALL_EVERY_S + rng.normal(0, 2)
        stride = 0.72 if late else 0.66
        at = start
        for i in range(RUNUP_STRIDES):
            speed = min(1.0, 0.55 + i * 0.05)  # accelerating
            strike(at, 3.5 + 4.5 * speed + rng.normal(0, 0.3))
            at += stride * (1.25 - 0.25 * speed)
        landing = (18.0 if not late else 15.5) + rng.normal(0, 0.8)
        strike(at, landing, 0.010)
        deliveries.append(float(at))
        strike(at + 0.55, 7.0 + rng.normal(0, 0.4))
        strike(at + 1.15, 4.5 + rng.normal(0, 0.3))
        for j in range(14):                   # walk back
            strike(at + 4 + j * 1.05, 1.9 + rng.normal(0, 0.1))
        hr_load.append((float(at), 22.0))

    g += rng.normal(0, 0.03, len(g))
    timed: list[tuple[int, str]] = [(0, "0,phone,event,,,,session_start")]
    for ti, gi in zip(t, g):
        ms = int(round(ti * 1000))
        ax, az = rng.normal(0, 0.15, 2)
        timed.append((ms, f"{ms},xiao,acc,{format_float(ax)},{format_float(gi * G)},{format_float(az)},"))
    if marks:
        for d in deliveries:
            ms = int((d + 1.5) * 1000)
            timed.append((ms, f"{ms},phone,event,,,,mark"))

    # Heart rate: jog ~140, each ball +22 bpm decaying with a 40 s time constant over a 120 base.
    for s in range(int(duration)):
        base = 70 + 70 * min(1, s / 120) if s < warmup_s else 120
        extra = sum(a * np.exp(-(s - b) / 40) for b, a in hr_load if s >= b)
        bpm = int(round(min(base + extra, 185) + rng.normal(0, 1)))
        timed.append((s * 1000, f"{s * 1000},whoop_hr,hr,,,,{bpm}"))
    end = int(duration * 1000)
    timed.append((end, f"{end},phone,event,,,,session_end"))
    timed.sort(key=lambda r: r[0])

    metadata = {
        "format_version": 1,
        "session_id": str(uuid.UUID(bytes=rng.bytes(16), version=4)),
        "athlete_id": None,
        "sport": "cricket",
        "session_type": "training",
        "started_at": datetime(2026, 12, 7, 4, 30, tzinfo=UTC).isoformat().replace("+00:00", "Z"),
        "app_version": "synthetic",
        "device_model": "synthetic",
        "sources": [{"id": "xiao", "kinds": ["acc"], "sample_rate_hz": RATE_HZ},
                    {"id": "whoop_hr", "kinds": ["hr"], "sample_rate_hz": 1}],
        "placement": "ankle",
        "notes": f"synthetic: fast-bowling spell, {balls} deliveries, last over softer",
    }
    return [",".join(HEADER)] + [r for _, r in timed], metadata, deliveries


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--out", default="output")
    parser.add_argument("--name", default="spell")
    parser.add_argument("--overs", type=int, default=3)
    parser.add_argument("--marks", action="store_true", help="include the coach's Mark taps")
    parser.add_argument("--seed", type=int, default=3)
    args = parser.parse_args()
    rows, meta, deliveries = generate(args.overs, args.marks, args.seed)
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    (out / f"{args.name}.csv").write_text("\n".join(rows) + "\n")
    (out / f"{args.name}.json").write_text(json.dumps(meta, indent=2) + "\n")
    print(f"wrote {out / args.name}.csv ({len(rows) - 1} rows, {len(deliveries)} deliveries) and .json")


if __name__ == "__main__":
    main()
