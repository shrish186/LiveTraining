import numpy as np
import pandas as pd

from check_rate import passes, rate_stats, report, session_rates


def stamps(hz: float, seconds: float) -> np.ndarray:
    """Integer ms timestamps, like the session file (800 Hz gives repeated ms values)."""
    return np.round(np.arange(0, seconds, 1 / hz) * 1000).astype(int)


def test_800hz_with_ms_rounding_passes():
    s = rate_stats(stamps(800, 30), "apple_watch", "acc")
    assert 790 <= s.mean_hz <= 810
    assert s.median_second_hz == 800
    assert s.gaps == 0
    assert passes(s, 800)


def test_100hz_fallback_fails_800_and_says_why():
    s = rate_stats(stamps(100, 30), "apple_watch", "acc")
    assert not passes(s, 800) and passes(s, 100)
    text = report([s], 800)
    assert "at 800 Hz: NO" in text and "fell back" in text


def test_dropout_shows_in_worst_seconds_and_gaps():
    t = stamps(800, 60)
    t = t[(t < 20000) | (t >= 23000)]  # 3 s with no data
    s = rate_stats(t, "apple_watch", "acc")
    assert s.median_second_hz == 800  # still 800 Hz most of the time
    assert s.worst_second_hz == 0
    assert s.gaps == 1 and s.longest_gap_ms >= 3000


def test_session_rates_per_stream_ignores_hr_and_events():
    acc = pd.DataFrame({"t_ms": stamps(800, 10), "source": "apple_watch", "kind": "acc"})
    gyro = pd.DataFrame({"t_ms": stamps(200, 10), "source": "apple_watch", "kind": "gyro"})
    other = pd.DataFrame({"t_ms": [0, 1000], "source": "whoop_hr", "kind": ["hr", "event"]})
    stats = {s.kind: s for s in session_rates(pd.concat([acc, gyro, other]))}
    assert set(stats) == {"acc", "gyro"}
    assert stats["acc"].median_second_hz == 800 and stats["gyro"].median_second_hz == 200
