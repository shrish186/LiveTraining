import numpy as np
import pandas as pd
import pytest

from analyze_session import analyze_steps, steps_text
from ltlib import core
from ltlib import steps as st
from ltlib.profiles import get_profile

HZ = 100


def gait(seconds: float, stride_s: float, own_g: float, other_g: float, quiet: float = 1.0):
    """Standing at 1 g, then running: our foot strikes every `stride_s` (peak `own_g`), the other
    foot halfway between (smaller, `other_g`)."""
    t = np.arange(0, seconds, 1 / HZ)
    g = np.ones_like(t)
    for k, strike in enumerate(np.arange(quiet, seconds - 0.1, stride_s / 2)):
        i = int(round(strike * HZ))
        g[i] = own_g if k % 2 == 0 else other_g
        g[i - 1] = g[i + 1] = 1 + (g[i] - 1) / 2
    return t, g


def jump(t: np.ndarray, g: np.ndarray, takeoff: float, flight: float, landing_g: float = 5.0):
    """Push-off, flight at ~0.3 g, landing spike, then standing still."""
    push = (t >= takeoff - 0.12) & (t < takeoff)
    g[push] = 2.6
    air = (t >= takeoff) & (t < takeoff + flight)
    g[air] = 0.3
    land = int(round((takeoff + flight) * HZ))
    g[land], g[land + 1], g[land + 2] = 1.8, landing_g, 2.0


def test_strikes_keep_our_foot_and_drop_the_other():
    t, g = gait(11, stride_s=0.6, own_g=12.0, other_g=5.0)
    strikes = st.detect_strikes(t, g, min_peak_g=2.0, min_interval_s=0.35)
    assert len(strikes) == 17
    assert all(s.peak_g == 12.0 for s in strikes)
    assert st.stride_times(strikes, 1.5) == pytest.approx(np.full(16, 0.6), abs=0.011)


def test_impact_load_and_weighting():
    strikes = [st.Strike(0, 10.0), st.Strike(1, 20.0)]
    assert st.impact_load(strikes) == 30
    assert st.impact_load(strikes, 2) == 500  # one 20 g hit outweighs two 10 g hits


def test_jump_height_from_flight_time():
    t = np.arange(0, 8, 1 / HZ)
    g = np.ones_like(t)
    jump(t, g, 2.0, 0.50)
    jump(t, g, 5.0, 0.30)
    jumps = st.detect_jumps(t, g, 2.0, 0.6, 1.5, 2.5, 0.08, 1.0, 0.8, 0.15)
    assert [round(j.flight_s, 2) for j in jumps] == [0.50, 0.30]
    assert jumps[0].height_cm == pytest.approx(30.7, abs=0.1)  # 9.81 * 0.5² / 8
    assert jumps[1].landing_peak_g == 5.0


def test_running_is_not_a_jump():
    t, g = gait(10, stride_s=0.6, own_g=12.0, other_g=5.0)
    g[(g > 0.99) & (g < 1.01) & (t > 1.5)] = 0.4  # flight phases between strides
    assert st.detect_jumps(t, g, 2.0, 0.6, 1.5, 2.5, 0.08, 1.0, 0.8, 0.15) == []


def test_effort_steps_and_drift():
    efforts = []
    for stride, peak in [(0.60, 10.0), (0.60, 10.0), (0.66, 9.0), (0.66, 9.0)]:
        t, g = gait(10, stride, peak, 4.0)
        efforts.append(st.effort_steps(st.detect_strikes(t, g, 2.0, 0.35), 0, 10, 1.5))
    assert efforts[0].strikes == 15 and efforts[0].peak_g == 10.0
    assert efforts[0].stride_ms == pytest.approx(600, abs=10)
    d = st.form_drift(efforts, 2)
    assert d.peak_g_pct == pytest.approx(-10)
    assert d.stride_ms == pytest.approx(60, abs=12)
    assert st.form_drift(efforts, 3) is None  # needs 2n efforts


def test_profile_has_step_settings_for_leg_placements_only():
    p = get_profile("soccer")
    assert "ankle" in p["steps"]["placements"] and "phone_pocket" not in p["steps"]["placements"]
    assert p["impact"]["weight_exponent"] == 2


def test_analyze_steps_report_only_for_leg_placements():
    t, g = gait(11, 0.6, 12.0, 5.0)
    acc = pd.DataFrame({"t_s": t, "x": 0.0, "y": g * 9.81, "z": 0.0})
    efforts = [core.Effort(1.0, 5.0, 30.0), core.Effort(5.0, 10.5, 30.0)]
    profile = get_profile("general")
    assert analyze_steps(profile, "phone_pocket", acc, efforts) is None
    r = analyze_steps(profile, "ankle", acc, efforts)
    assert len(r["strikes"]) == 17 and r["impact_load"] == pytest.approx(17 * 12.0)
    text = "\n".join(steps_text(r))
    assert "17 footstrikes" in text and "impact load 204 g" in text
    assert "injur" not in text.lower()
