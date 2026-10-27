"""Did a session really record at the rate you asked for (e.g. the watch's 800 Hz)?

Usage: python check_rate.py <csv> [--metadata <json>] [--expect 800]

For each motion stream it prints the samples per second it really got: overall, in a typical
second and in the worst second. It also counts dropouts (gaps over 50 ms). --expect defaults to
the metadata's requested_rate_hz (the watch app writes it). A stream passes when its median
second reaches 95 % of the expected rate.
"""

import argparse
import sys
from dataclasses import dataclass
from pathlib import Path

import numpy as np
import pandas as pd

from ltlib.session_io import load_metadata, load_session_csv

GAP_MS = 50


@dataclass
class RateStats:
    source: str
    kind: str
    samples: int
    duration_s: float
    mean_hz: float
    median_second_hz: float   # samples in a typical whole second
    worst_second_hz: float    # fewest samples in any whole second
    gaps: int                 # intervals over GAP_MS
    longest_gap_ms: float


def rate_stats(t_ms: np.ndarray, source: str, kind: str) -> RateStats:
    t = np.sort(t_ms.astype(float))
    duration = (t[-1] - t[0]) / 1000 if len(t) > 1 else 0.0
    # Whole seconds only, so a partial first or last second doesn't look like a dropout.
    sec = np.floor((t - t[0]) / 1000).astype(int)
    per_second = np.bincount(sec)[: max(int(duration), 1)] if len(t) else np.array([0])
    dt = np.diff(t)
    return RateStats(
        source, kind, len(t), duration,
        mean_hz=len(t) / duration if duration else 0.0,
        median_second_hz=float(np.median(per_second)),
        worst_second_hz=float(per_second.min()),
        gaps=int((dt > GAP_MS).sum()),
        longest_gap_ms=float(dt.max()) if len(dt) else 0.0,
    )


def session_rates(df: pd.DataFrame) -> list[RateStats]:
    out = []
    for (source, kind), g in df[df["kind"].isin(["acc", "gyro"])].groupby(["source", "kind"]):
        out.append(rate_stats(g["t_ms"].to_numpy(), str(source), str(kind)))
    return out


def passes(s: RateStats, expect_hz: float) -> bool:
    return s.median_second_hz >= 0.95 * expect_hz


def report(stats: list[RateStats], expect_hz: float | None) -> str:
    if not stats:
        return "No acc or gyro rows in this session."
    lines = ["  stream            samples   length   overall  typical second  worst second   dropouts>50ms  longest gap"]
    for s in stats:
        lines.append(f"  {s.source + '/' + s.kind:<16} {s.samples:8d}  {s.duration_s:6.0f} s  {s.mean_hz:6.0f} Hz"
                     f"  {s.median_second_hz:10.0f} Hz  {s.worst_second_hz:9.0f} Hz  {s.gaps:13d}"
                     f"  {s.longest_gap_ms:8.0f} ms")
    if expect_hz:
        acc = [s for s in stats if s.kind == "acc"]
        lines.append("")
        for s in acc:
            verdict = "YES" if passes(s, expect_hz) else "NO"
            lines.append(f"{s.source} accelerometer at {expect_hz:.0f} Hz: {verdict} "
                         f"(typical second {s.median_second_hz:.0f} Hz)")
            if not passes(s, expect_hz) and 90 <= s.median_second_hz <= 110:
                lines.append("  It recorded at about 100 Hz, the standard rate. On the watch, 800 Hz fell back "
                             "to 100 Hz; the watch shows why under the timer.")
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("csv")
    parser.add_argument("--metadata", help="session metadata JSON (default: <csv>.json if it exists)")
    parser.add_argument("--expect", type=float, help="expected Hz (default: metadata requested_rate_hz)")
    args = parser.parse_args()
    csv_path = Path(args.csv)
    metadata = args.metadata or (csv_path.with_suffix(".json") if csv_path.with_suffix(".json").exists() else None)
    try:
        df = load_session_csv(csv_path)
    except (KeyError, ValueError) as exc:
        sys.exit(f"error: {exc}")
    expect = args.expect or load_metadata(metadata).get("requested_rate_hz")
    print(report(session_rates(df), expect))


if __name__ == "__main__":
    main()
