import json

import numpy as np
import pandas as pd

import make_synthetic_session as syn
from analyze_session import analyze
from ltlib import core
from ltlib.validate import match, suggest, sweep
from validate_session import report


def series(values, hz=core.GRID_HZ):
    return pd.Series(values, index=np.arange(len(values)) / hz, dtype=float)


def test_match_counts_hits_misses_and_extras():
    efforts = [core.Effort(10, 20, 8), core.Effort(50, 60, 8), core.Effort(100, 110, 8)]
    s = match([22.0, 61.0, 200.0], efforts, threshold=5)  # 2 inside a window, 1 far from any effort
    assert [m for m, _ in s.matched] == [22.0, 61.0]
    assert s.missed_marks == [200.0]
    assert [e.start_s for e in s.extra_efforts] == [100]
    assert s.precision == 2 / 3 and s.recall == 2 / 3


def test_one_mark_per_effort():
    s = match([12.0, 14.0], [core.Effort(10, 20, 8)], threshold=5)
    assert len(s.matched) == 1 and s.missed_marks == [14.0]


def test_mark_window_before_and_after():
    e = [core.Effort(10, 20, 8)]
    assert len(match([5.0], e, 5, before_s=5).matched) == 1
    assert len(match([4.9], e, 5, before_s=5).matched) == 0
    assert len(match([35.0], e, 5, after_s=15).matched) == 1
    assert len(match([35.1], e, 5, after_s=15).matched) == 0


def test_no_marks_gives_no_suggestion():
    mag = series([0] * 50 + [8] * 50 + [0] * 50)
    assert suggest(sweep(mag, [], np.array([3.0, 5.0]), 1, 0), 5.0) is None


def test_sweep_finds_threshold_between_noise_and_efforts():
    # Real efforts reach 7; a noisy patch reaches 4.5 (counts as an effort at low thresholds).
    values = [1] * 100 + [7] * 50 + [1] * 100 + [4.5] * 50 + [1] * 100 + [7] * 50 + [1] * 100
    mag = series(values)
    marks = [16.0, 41.0]  # just after the two real efforts
    scores = sweep(mag, marks, np.arange(2.0, 9.01, 0.5), min_duration_s=2, merge_gap_s=0)
    best = suggest(scores, current=3.0)
    assert best is not None and best.f1 == 1.0
    assert 4.5 <= best.threshold < 7  # middle of the band that keeps both efforts and drops the noise
    assert best.threshold == 5.5
    low = next(s for s in scores if s.threshold == 3.0)
    assert len(low.extra_efforts) == 1 and low.precision == 2 / 3


def test_synthetic_session_with_marks_scores_perfectly(tmp_path):
    rows, meta = syn.generate(rate_hz=20, seed=11)
    marks = [f"{int((start + syn.EFFORT_S + 3) * 1000)},phone,event,,,,mark" for start, _, _ in syn.EFFORTS]
    body = sorted(rows[1:] + marks, key=lambda r: int(r.split(",")[0]))
    (tmp_path / "s.csv").write_text("\n".join([rows[0], *body]) + "\n")
    (tmp_path / "s.json").write_text(json.dumps(meta))
    r = analyze(tmp_path / "s.csv", tmp_path / "s.json")
    text = report(r, "mark", 5, 15)
    assert f"Marks labelled 'mark': {len(syn.EFFORTS)}" in text
    assert "precision  100%   recall  100%" in text
    assert "MISSED" not in text and "EXTRA" not in text
    assert "No change suggested" in text
