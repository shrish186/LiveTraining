import numpy as np
import pandas as pd
import pytest

from ltlib import core
from ltlib.profiles import effort_params, get_profile, load_profiles
from ltlib.session_io import format_float


def series(values, hz=core.GRID_HZ):
    return pd.Series(values, index=np.arange(len(values)) / hz, dtype=float)


def test_dynamic_magnitude_removes_gravity_any_orientation():
    for x, y, z in [(0, 9.81, 0), (9.81, 0, 0), (0, 0, -9.81), (5.6638, 5.6638, 5.6638)]:
        assert core.dynamic_magnitude(np.array([x]), np.array([y]), np.array([z]))[0] == pytest.approx(0, abs=1e-3)
    assert core.dynamic_magnitude(np.array([0.0]), np.array([0.0]), np.array([0.0]))[0] == pytest.approx(9.81)


def test_smooth_on_grid_bins_and_averages():
    t = np.arange(0, 10, 0.01)  # 100 Hz for 10 s
    s = core.smooth_on_grid(t, np.full_like(t, 3.0), window_s=1.0)
    assert len(s) == 100
    assert s.index[1] == pytest.approx(0.1)
    assert np.allclose(s.to_numpy(), 3.0)


def test_detect_efforts_threshold_and_min_duration():
    values = [0] * 20 + [8] * 40 + [0] * 20 + [8] * 10 + [0] * 20  # 4 s burst, then 1 s burst
    efforts = core.detect_efforts(series(values), threshold=5, min_duration_s=3)
    assert len(efforts) == 1
    assert efforts[0].start_s == pytest.approx(2.0)
    assert efforts[0].duration_s == pytest.approx(4.0)
    assert efforts[0].peak == 8


def test_detect_efforts_merges_short_gaps():
    values = [0] * 10 + [8] * 20 + [0] * 5 + [9] * 20 + [0] * 10  # 0.5 s dip in the middle
    assert len(core.detect_efforts(series(values), 5, 1, merge_gap_s=0)) == 2
    merged = core.detect_efforts(series(values), 5, 1, merge_gap_s=1.0)
    assert len(merged) == 1
    assert merged[0].peak == 9


def test_detect_efforts_empty():
    assert core.detect_efforts(pd.Series(dtype=float), 5, 1) == []


def test_hr_recovery_and_window_rules():
    hr_t = np.arange(0, 400, 1.0)
    hr_v = np.where(hr_t < 100, 170 - 0.5 * np.maximum(hr_t - 30, 0), 120.0)
    efforts = [core.Effort(0, 30, 8), core.Effort(60, 70, 8), core.Effort(300, 310, 8), core.Effort(500, 510, 8)]
    core.add_hr_recovery(efforts, hr_t, hr_v, window_s=60)
    assert efforts[0].hr_recovery_bpm is None and "next effort" in efforts[0].notes[0]
    assert efforts[1].hr_recovery_bpm == pytest.approx(150 - 120)  # HR(70)=150, HR(130)=120
    assert efforts[2].hr_recovery_bpm == pytest.approx(0)
    assert efforts[3].hr_recovery_bpm is None and efforts[3].notes == ["no HR coverage"]


def make(start_min, peak, hrr):
    return core.Effort(start_min * 60, start_min * 60 + 20, peak, hr_recovery_bpm=hrr)


def test_fatigue_needs_both_peak_drop_and_slower_recovery():
    efforts = [make(5, 10, 50), make(10, 10, 50),   # baseline: peak 10, HRR 50
               make(20, 9.6, 40),                     # -4% peak, slower HR -> not enough peak drop
               make(25, 9.0, 55),                     # -10% peak, faster HR -> no
               make(30, 9.0, 40)]                     # -10% peak, slower HR -> fatigue
    result = core.assess_fatigue(efforts, baseline_window_s=15 * 60, peak_drop_pct=5)
    assert result.baseline_peak == 10 and result.baseline_hr_recovery == 50
    assert [e.fatigue for e in efforts] == [False, False, False, False, True]
    assert efforts[2].peak_drop_pct == pytest.approx(4)
    assert result.first_flagged is efforts[4]


def test_fatigue_exactly_five_percent_counts():
    efforts = [make(1, 10, 50), make(20, 9.5, 49)]
    assert core.assess_fatigue(efforts, 900, 5).first_flagged is efforts[1]


def test_fatigue_without_baseline_or_hr():
    assert core.assess_fatigue([make(20, 5, 10)], 900, 5).baseline_peak is None
    efforts = [make(1, 10, None), make(20, 5, 10)]
    assert core.assess_fatigue(efforts, 900, 5).first_flagged is None  # no HR baseline -> no flag


def test_profiles_merge_over_general():
    profiles = load_profiles()
    assert {"general", "soccer"} <= set(profiles)
    soccer = get_profile("soccer")
    assert soccer["fatigue"] == profiles["general"]["fatigue"]  # inherited
    assert soccer["effort"]["min_duration_s"] == 2.0               # overridden
    assert soccer["effort"]["merge_gap_s"] == 1.0                  # inherited inside a nested block
    assert get_profile(None)["name"] == "general"
    with pytest.raises(KeyError):
        get_profile("curling")


def test_effort_params_placement_override():
    soccer = get_profile("soccer")
    assert effort_params(soccer, "shin")["threshold"] == 8.0
    assert effort_params(soccer, "shin")["min_duration_s"] == 2.0
    assert effort_params(soccer, "phone_armband")["threshold"] == 5.5
    assert effort_params(soccer, None)["threshold"] == 5.5


def test_format_float():
    assert format_float(9.81) == "9.81"
    assert format_float(0.000001) == "0"
    assert format_float(-0.000001) == "0"
    assert format_float(1.234567) == "1.23457"
    assert format_float(12.0) == "12"
