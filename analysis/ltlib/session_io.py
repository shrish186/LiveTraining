"""Read and write session files. Spec: docs/session-format.md."""

import json
from pathlib import Path
from typing import Any

import pandas as pd

HEADER = ["t_ms", "source", "kind", "x", "y", "z", "value"]


def load_session_csv(path: str | Path) -> pd.DataFrame:
    """Loads the long-format CSV, sorted by t_ms. `value` stays text because event labels live there."""
    df = pd.read_csv(path, dtype={"source": str, "kind": str, "value": str}, keep_default_na=False,
                     na_values={"x": [""], "y": [""], "z": [""]})
    if list(df.columns) != HEADER:
        raise ValueError(f"{path}: header must be exactly {','.join(HEADER)}")
    return df.sort_values("t_ms", kind="stable").reset_index(drop=True)


def load_metadata(path: str | Path | None) -> dict[str, Any]:
    if path is None:
        return {}
    return json.loads(Path(path).read_text())


def motion_rows(df: pd.DataFrame, kind: str = "acc", source: str | None = None) -> pd.DataFrame:
    """acc or gyro rows as t_s, x, y, z. Picks the first motion source present unless `source` is given."""
    rows = df[df["kind"] == kind]
    if source is None and not rows.empty:
        source = rows["source"].iloc[0]
    rows = rows[rows["source"] == source] if source else rows
    return pd.DataFrame({"t_s": rows["t_ms"].to_numpy() / 1000.0, "x": rows["x"].to_numpy(dtype=float),
                         "y": rows["y"].to_numpy(dtype=float), "z": rows["z"].to_numpy(dtype=float)})


def scalar_rows(df: pd.DataFrame, kind: str) -> pd.DataFrame:
    rows = df[df["kind"] == kind]
    return pd.DataFrame({"t_s": rows["t_ms"].to_numpy() / 1000.0, "value": rows["value"].astype(float).to_numpy()})


def event_rows(df: pd.DataFrame) -> list[tuple[float, str]]:
    rows = df[df["kind"] == "event"]
    return [(t / 1000.0, label) for t, label in zip(rows["t_ms"], rows["value"])]


def format_float(v: float) -> str:
    """Up to 5 decimals, no trailing zeros, as in the spec."""
    text = f"{v:.5f}".rstrip("0").rstrip(".")
    return "0" if text in ("-0", "") else text
