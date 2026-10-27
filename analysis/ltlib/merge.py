"""Merge two recordings of the same session from different devices (e.g. phone + Apple Watch).

Alignment:
1. Wall clock: the difference between the two `started_at` values (ms precision). The watch takes
   its time from the iPhone, so this is usually within a few tens of ms.
2. Sync jumps (optional refinement): around the base recording's `sync_jumps` event, cross-correlate
   the two acceleration magnitudes and take the best lag within +-search window. Only used when the
   match is clearly good (correlation >= MIN_CORRELATION).
"""

import uuid
from dataclasses import dataclass
from datetime import UTC, datetime
from typing import Any

import numpy as np
import pandas as pd

from .core import dynamic_magnitude

GRID_MS = 10
MIN_CORRELATION = 0.5


@dataclass
class MergeInfo:
    clock_offset_ms: int
    offset_ms: int
    method: str  # "clock" or "sync_jumps"
    correlation: float | None = None


def parse_time(text: str) -> datetime:
    dt = datetime.fromisoformat(text.replace("Z", "+00:00"))
    return dt if dt.tzinfo else dt.replace(tzinfo=UTC)


def clock_offset_ms(base_meta: dict[str, Any], other_meta: dict[str, Any]) -> int:
    """Add this to the other recording's t_ms to put it on the base recording's timeline."""
    delta = parse_time(other_meta["started_at"]) - parse_time(base_meta["started_at"])
    return round(delta.total_seconds() * 1000)


def _magnitude(df: pd.DataFrame) -> tuple[np.ndarray, np.ndarray]:
    acc = df[df["kind"] == "acc"].sort_values("t_ms")
    t = acc["t_ms"].to_numpy(dtype=float)
    mag = dynamic_magnitude(acc["x"].to_numpy(dtype=float), acc["y"].to_numpy(dtype=float),
                            acc["z"].to_numpy(dtype=float))
    return t, mag


def refine_offset(base_df: pd.DataFrame, other_df: pd.DataFrame, approx_offset_ms: int,
                  search_ms: int = 2000, before_ms: int = 3000, after_ms: int = 10000) -> tuple[int, float] | None:
    """Best offset near `approx_offset_ms` by matching motion around the base's sync_jumps event.
    Returns (offset_ms, correlation) or None if there is nothing to match on."""
    jumps = base_df[(base_df["kind"] == "event") & (base_df["value"] == "sync_jumps")]
    bt, bmag = _magnitude(base_df)
    ot, omag = _magnitude(other_df)
    if jumps.empty or len(bt) < 10 or len(ot) < 10:
        return None
    t0 = float(jumps["t_ms"].iloc[0])
    grid = np.arange(t0 - before_ms, t0 + after_ms, GRID_MS)
    if grid[0] < bt[0] or grid[-1] > bt[-1]:
        grid = grid[(grid >= bt[0]) & (grid <= bt[-1])]
    if len(grid) < 50:
        return None
    base_sig = np.interp(grid, bt, bmag)
    ot_shifted = ot + approx_offset_ms

    best: tuple[int, float] | None = None
    for lag in range(-search_ms, search_ms + 1, GRID_MS):
        # Compare base(t) with other(t) under offset approx + lag.
        other_sig = np.interp(grid - lag, ot_shifted, omag, left=np.nan, right=np.nan)
        ok = ~np.isnan(other_sig)
        if ok.sum() < 50:
            continue
        a, b = base_sig[ok], other_sig[ok]
        if a.std() == 0 or b.std() == 0:
            continue
        r = float(np.corrcoef(a, b)[0, 1])
        if best is None or r > best[1]:
            best = (approx_offset_ms + lag, r)
    return best


def merge_sessions(base_df: pd.DataFrame, base_meta: dict[str, Any], other_df: pd.DataFrame,
                   other_meta: dict[str, Any], refine: bool = True) -> tuple[pd.DataFrame, dict[str, Any], MergeInfo]:
    """Puts `other` on `base`'s timeline and combines them. Returns (rows, metadata, alignment info)."""
    approx = clock_offset_ms(base_meta, other_meta)
    info = MergeInfo(clock_offset_ms=approx, offset_ms=approx, method="clock")
    if refine:
        found = refine_offset(base_df, other_df, approx)
        if found and found[1] >= MIN_CORRELATION:
            info.offset_ms, info.correlation, info.method = found[0], round(found[1], 3), "sync_jumps"

    shifted = other_df.copy()
    shifted["t_ms"] = shifted["t_ms"] + info.offset_ms
    shifted = shifted[shifted["t_ms"] >= 0]
    rows = pd.concat([base_df, shifted], ignore_index=True).sort_values("t_ms", kind="stable").reset_index(drop=True)

    other_motion = next((s for s in dict.fromkeys(other_df.loc[other_df["kind"] == "acc", "source"])), None)
    base_hr = set(base_df.loc[base_df["kind"] == "hr", "source"])
    meta = dict(base_meta)
    meta.update(
        session_id=str(uuid.uuid4()),
        sources=list(base_meta.get("sources", [])) + list(other_meta.get("sources", [])),
        placement=other_meta.get("placement", base_meta.get("placement")),
        motion_source=other_motion,
        hr_source="whoop_hr" if "whoop_hr" in base_hr else None,
        duration_ms=int(rows["t_ms"].max() - rows["t_ms"].min()) if len(rows) else 0,
        merged_from=[base_meta.get("session_id"), other_meta.get("session_id")],
        alignment={"method": info.method, "offset_ms": info.offset_ms, "clock_offset_ms": info.clock_offset_ms,
                   "correlation": info.correlation},
        notes=" | ".join(n for n in (base_meta.get("notes"), other_meta.get("notes")) if n),
        complete=bool(base_meta.get("complete", True) and other_meta.get("complete", True)),
    )
    return rows, meta, info
