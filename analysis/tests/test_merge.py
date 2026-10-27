import json
import subprocess
import sys
from pathlib import Path

import numpy as np
import pandas as pd
import pytest

import make_synthetic_session
from ltlib.merge import clock_offset_ms, merge_sessions
from ltlib.session_io import load_session_csv

ANALYSIS = Path(__file__).resolve().parents[1]


def watch_copy(phone_df: pd.DataFrame, true_offset_ms: int, seed: int = 1) -> pd.DataFrame:
    """A 'watch' recording of the same motion: the phone's acc rows, renamed, on a clock that
    started `true_offset_ms` after the phone's, with extra noise and no HR or events."""
    rng = np.random.default_rng(seed)
    acc = phone_df[phone_df["kind"] == "acc"].copy()
    acc["source"] = "apple_watch"
    acc["t_ms"] = acc["t_ms"] - true_offset_ms
    acc = acc[acc["t_ms"] >= 0]
    for axis in ("x", "y", "z"):
        acc[axis] = acc[axis] + rng.normal(0, 0.3, len(acc))
    return acc.reset_index(drop=True)


@pytest.fixture(scope="module")
def phone(tmp_path_factory):
    rows, meta = make_synthetic_session.generate(rate_hz=50, seed=5)
    path = tmp_path_factory.mktemp("merge") / "phone.csv"
    path.write_text("\n".join(rows) + "\n")
    meta["started_at"] = "2026-10-27T18:00:00.000Z"
    return load_session_csv(path), meta


def watch_meta(started_at: str) -> dict:
    return {"session_id": "w", "sport": "soccer", "session_type": "training", "started_at": started_at,
            "placement": "ankle", "sources": [{"id": "apple_watch", "kinds": ["acc"], "sample_rate_hz": 50}]}


def test_clock_offset():
    a = {"started_at": "2026-10-27T18:00:00.000Z"}
    assert clock_offset_ms(a, {"started_at": "2026-10-27T18:00:01.250Z"}) == 1250
    assert clock_offset_ms(a, {"started_at": "2026-10-27T17:59:59.900Z"}) == -100
    assert clock_offset_ms({"started_at": "2026-10-27T18:00:00Z"}, {"started_at": "2026-10-27T18:00:00.5Z"}) == 500


def test_sync_jumps_correct_a_wrong_clock(phone):
    phone_df, phone_meta = phone
    true_offset = 1200  # watch started 1.2 s after the phone...
    watch_df = watch_copy(phone_df, true_offset)
    # ...but its clock claims 1.55 s (350 ms error).
    rows, meta, info = merge_sessions(phone_df, phone_meta, watch_df, watch_meta("2026-10-27T18:00:01.550Z"))
    assert info.clock_offset_ms == 1550
    assert info.method == "sync_jumps"
    assert abs(info.offset_ms - true_offset) <= 20
    assert info.correlation > 0.8

    assert meta["motion_source"] == "apple_watch"
    assert meta["hr_source"] == "whoop_hr"
    assert meta["placement"] == "ankle"
    assert meta["merged_from"] == [phone_meta["session_id"], "w"]
    assert {s["id"] for s in meta["sources"]} == {"phone", "whoop_hr", "apple_watch"}
    assert set(rows["source"]) == {"phone", "whoop_hr", "apple_watch"}
    assert rows["t_ms"].is_monotonic_increasing


def test_falls_back_to_clock_without_a_match(phone):
    phone_df, phone_meta = phone
    rng = np.random.default_rng(3)
    noise = pd.DataFrame({"t_ms": np.arange(0, 60000, 20), "source": "apple_watch", "kind": "acc",
                          "x": rng.normal(0, 1, 3000), "y": 9.81 + rng.normal(0, 1, 3000),
                          "z": rng.normal(0, 1, 3000), "value": ""})
    _, _, info = merge_sessions(phone_df, phone_meta, noise, watch_meta("2026-10-27T18:00:00.400Z"))
    assert info.method == "clock"
    assert info.offset_ms == 400


def test_cli_merge_then_analyze(tmp_path, phone):
    """End to end: files on disk -> merge_sessions.py -> analyze_session.py uses the watch motion."""
    phone_df, phone_meta = phone
    rows, _ = make_synthetic_session.generate(rate_hz=50, seed=5)
    (tmp_path / "phone.csv").write_text("\n".join(rows) + "\n")
    (tmp_path / "phone.json").write_text(json.dumps(phone_meta))
    watch_copy(phone_df, 800).to_csv(tmp_path / "watch.csv", index=False)
    # The synthetic motion is phone-level, so describe the copy as wrist-worn (no lower-leg threshold).
    (tmp_path / "watch.json").write_text(json.dumps(watch_meta("2026-10-27T18:00:00.800Z") | {"placement": "wrist"}))

    out = tmp_path / "merged.csv"
    run = subprocess.run([sys.executable, "merge_sessions.py", str(tmp_path / "phone.csv"), str(tmp_path / "watch.csv"),
                          "--out", str(out)], cwd=ANALYSIS, capture_output=True, text=True, check=True)
    assert "Aligned by sync jumps" in run.stdout

    import analyze_session

    result = analyze_session.analyze(out, out.with_suffix(".json"))
    assert result["motion_source"] == "apple_watch"
    assert result["hr_source"] == "whoop_hr"
    assert len(result["efforts"]) == 6

    backend = ANALYSIS.parent / "backend"
    sys.path.insert(0, str(backend))
    try:
        from app.session_format import validate_and_summarize
    finally:
        sys.path.remove(str(backend))
    with open(out) as f:
        assert "apple_watch" in validate_and_summarize(f).sources
