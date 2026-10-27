"""Convert a SensorLog (App Store app) Apple Watch recording into a session (docs/session-format.md).

Usage: python import_sensorlog.py "<SensorLog file>.csv" [--placement ankle] [--sport general]
                                  [--session-type training] [--out output/]

Keeps only the accelerometer (G -> m/s², gravity included) and the rotation rate (rad/s), as
source `apple_watch`. Location, heart rate and everything else SensorLog logs are dropped. Use
WHOOP heart rate from the phone session instead. Writes <out>/<session_id>.csv and .json, then:

  python merge_sessions.py <phone session>.csv output/<session_id>.csv
  python analyze_session.py output/merged_<phone session id>.csv

The raw SensorLog file contains GPS coordinates: never commit it.
"""

import argparse
import json
import uuid
from datetime import UTC, datetime
from pathlib import Path

import numpy as np
import pandas as pd

from ltlib.core import GRAVITY
from ltlib.session_io import HEADER, format_float

SOURCE = "apple_watch"
TIME = "loggingTime(txt)"
ACC_T = "accelerometerTimestamp_sinceReboot(s)"
ACC = [f"accelerometerAcceleration{a}(G)" for a in "XYZ"]
GYRO_T = "motionTimestamp_sinceReboot(s)"
GYRO = [f"motionRotationRate{a}(rad/s)" for a in "XYZ"]


def _vector_rows(df: pd.DataFrame, t_col: str, cols: list[str], kind: str, t0: float, scale: float) -> list[tuple]:
    if t_col not in df.columns or not all(c in df.columns for c in cols):
        return []
    part = df[[t_col, *cols]].apply(pd.to_numeric, errors="coerce").dropna()
    part = part.drop_duplicates(subset=t_col)  # SensorLog repeats the last sample when a stream lags
    t_ms = np.round((part[t_col].to_numpy() - t0) * 1000).astype(int)
    keep = t_ms >= 0
    values = part[cols].to_numpy()[keep] * scale
    return [(int(t), kind, *(format_float(float(v)) for v in row)) for t, row in zip(t_ms[keep], values)]


def convert(df: pd.DataFrame, placement: str, sport: str = "general", session_type: str = "training",
            session_id: str | None = None) -> tuple[list[str], dict]:
    """SensorLog rows -> (session CSV lines incl. header, metadata). t_ms 0 = first accelerometer sample."""
    missing = [c for c in [TIME, ACC_T, *ACC] if c not in df.columns]
    if missing:
        raise ValueError(f"not a SensorLog accelerometer file: missing {', '.join(missing)}")
    acc_t = pd.to_numeric(df[ACC_T], errors="coerce")
    first = int(acc_t.first_valid_index())
    t0 = float(acc_t[first])
    started = datetime.fromisoformat(str(df.loc[first, TIME])).astimezone(UTC)

    samples = (_vector_rows(df, ACC_T, ACC, "acc", t0, GRAVITY)
               + _vector_rows(df, GYRO_T, GYRO, "gyro", t0, 1.0))
    samples.sort(key=lambda r: r[0])
    duration_ms = samples[-1][0] if samples else 0
    lines = [",".join(HEADER), f"0,{SOURCE},event,,,,session_start"]
    lines += [f"{t},{SOURCE},{kind},{x},{y},{z}," for t, kind, x, y, z in samples]

    kinds = sorted({r[1] for r in samples})
    n_acc = sum(1 for r in samples if r[1] == "acc")
    meta = {
        "format_version": 1,
        "session_id": session_id or str(uuid.uuid4()),
        "athlete_id": None,
        "sport": sport,
        "session_type": session_type,
        "started_at": started.isoformat(timespec="milliseconds").replace("+00:00", "Z"),
        "app_version": "SensorLog import",
        "device_model": "Apple Watch (SensorLog)",
        "sources": [{"id": SOURCE, "kinds": kinds,
                     "sample_rate_hz": round(n_acc / (duration_ms / 1000), 1) if duration_ms else None}],
        "placement": placement,
        "notes": "imported from SensorLog",
        "duration_ms": duration_ms,
        "complete": True,
    }
    return lines, meta


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("csv")
    parser.add_argument("--placement", default="ankle", help="where the watch was worn (default: ankle)")
    parser.add_argument("--sport", default="general")
    parser.add_argument("--session-type", default="training")
    parser.add_argument("--out", default="output", help="output folder (default: output/)")
    args = parser.parse_args()

    df = pd.read_csv(args.csv, low_memory=False)
    lines, meta = convert(df, args.placement, args.sport, args.session_type)
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    csv_path = out / f"{meta['session_id']}.csv"
    csv_path.write_text("\n".join(lines) + "\n")
    csv_path.with_suffix(".json").write_text(json.dumps(meta, indent=2) + "\n")
    src = meta["sources"][0]
    print(f"{len(lines) - 2} samples ({', '.join(src['kinds'])}) at {src['sample_rate_hz']} Hz, "
          f"{meta['duration_ms'] / 1000:.1f} s, started {meta['started_at']}, placement {meta['placement']}")
    print(f"Wrote {csv_path} and {csv_path.with_suffix('.json')}")


if __name__ == "__main__":
    main()
