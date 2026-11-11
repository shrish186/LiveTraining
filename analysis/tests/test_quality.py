import numpy as np
import pytest

from ltlib import quality as ql
from ltlib.profiles import get_profile

CFG = get_profile("general")["quality"]
G = 9.81


def still(seconds: float, hz: int = 100, axis=(0.0, G, 0.0), noise: float = 0.02, seed: int = 1):
    """A sensor at rest: gravity on one axis plus a little noise."""
    rng = np.random.default_rng(seed)
    t = np.arange(0, seconds, 1 / hz)
    acc = np.tile(np.array(axis, dtype=float), (len(t), 1)) + rng.normal(0, noise, (len(t), 3))
    return t, acc


def check(t, acc):
    return ql.stream_quality(t, acc[:, 0], acc[:, 1], acc[:, 2], **CFG)


def test_clean_stream_is_good():
    q = check(*still(60))
    assert q.rate_hz == 100 and q.gaps == 0 and q.lost_pct < 0.5
    assert q.clip_level_g is None
    assert q.gravity_error_pct < 1 and q.tilt_change_deg < 2
    assert q.grade == "good" and q.score == 100 and q.issues == []


def test_dropout_and_lost_samples():
    t, acc = still(60)
    keep = (t < 20) | (t >= 23)  # 3 s with nothing
    q = check(t[keep], acc[keep])
    assert q.gaps == 1 and q.longest_gap_s == pytest.approx(3.0, abs=0.02)
    assert q.lost_pct == pytest.approx(5.0, abs=0.3)
    assert q.grade != "good"
    assert any("dropout" in i for i in q.issues) and any("missing" in i for i in q.issues)


def test_clipping_is_found_and_single_peaks_are_not():
    t, acc = still(30)
    acc[500, 1] = 20 * G  # one real impact peak
    assert check(t, acc).clip_level_g is None
    acc[1000:1012, 1] = 16 * G  # a landing held at the sensor's ±16 g limit
    acc[500, 1] = 15 * G
    q = check(t, acc)
    assert q.clip_level_g == pytest.approx(16, abs=0.1)
    assert any("limit" in i for i in q.issues)


def test_gravity_error_and_strap_moved():
    t, acc = still(40, axis=(0.0, G * 1.12, 0.0))  # reads 12 % high
    q = check(t, acc)
    assert q.gravity_error_pct == pytest.approx(12, abs=1)
    assert any("calibration" in i for i in q.issues)

    t, acc = still(40)
    acc[t >= 20] = still(20, axis=(G, 0.0, 0.0))[1]  # rotated 90° halfway
    q = check(t, acc)
    assert q.tilt_change_deg == pytest.approx(90, abs=2)
    assert any("strap" in i for i in q.issues)


def test_too_little_data():
    t, acc = still(0.1)
    assert check(t, acc) is None


def test_hr_coverage():
    assert ql.hr_coverage_pct(np.arange(0, 100, 1.0), 100) == 100
    assert ql.hr_coverage_pct(np.arange(0, 50, 1.0), 100) == pytest.approx(55, abs=1)  # 5 s grace
    assert ql.hr_coverage_pct(np.array([]), 100) == 0


def test_fuse_ranges_uses_low_when_small_and_high_when_clipped():
    true = np.array([[0.5, 1.0, 0.2], [10.0, 0.0, 0.0], [15.0, 0.0, 0.0], [40.0, 3.0, 0.0]])
    low = np.clip(true, -16, 16)                      # precise, clips at 16 g
    high = true + np.array([0.3, -0.3, 0.3])           # coarse, never clips
    out = ql.fuse_ranges(low, high, low_limit=16, blend_from=12)
    assert np.allclose(out[0], low[0]) and np.allclose(out[1], low[1])   # below the blend: low only
    assert np.allclose(out[3], high[3])                                   # clipped: high only
    assert low[2, 0] < out[2, 0] < high[2, 0]                             # in between: blended


def test_fit_clock_recovers_drift_and_offset_despite_radio_delay():
    rng = np.random.default_rng(3)
    sensor = np.arange(0, 600, 0.5)                      # sensor seconds
    true_scale, true_offset = 1.00004, 12.345            # 40 ppm drift
    received = true_scale * sensor + true_offset + rng.exponential(0.03, len(sensor))  # late, never early
    scale, offset = ql.fit_clock(sensor, received)
    predicted = scale * sensor + offset
    assert np.abs(predicted - (true_scale * sensor + true_offset)).max() < 0.005   # within 5 ms
