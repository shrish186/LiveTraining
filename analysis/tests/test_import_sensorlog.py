import json

import numpy as np
import pandas as pd
import pytest

from import_sensorlog import ACC, ACC_T, GYRO, GYRO_T, TIME, convert
from ltlib.session_io import load_session_csv


def sensorlog_frame(n: int = 300, hz: float = 100.0) -> pd.DataFrame:
    """A minimal SensorLog export: watch still (gravity on -Y), clock since reboot starting at 6352 s."""
    t = 6352.0 + np.arange(n) / hz
    return pd.DataFrame({
        TIME: [f"2026-10-27T12:11:17.{313 + i // 100:03d}-04:00" for i in range(n)],
        "locationLatitude(WGS84)": 42.38,  # must not survive the import
        ACC_T: t, ACC[0]: 0.0, ACC[1]: -1.0, ACC[2]: 0.0,
        GYRO_T: t - 0.001, GYRO[0]: 0.1, GYRO[1]: 0.0, GYRO[2]: -0.1,
        "heartRateBPM(N)": 81,
    })


def test_convert_units_clock_and_metadata(tmp_path):
    lines, meta = convert(sensorlog_frame(), placement="ankle", session_id="s1")
    assert lines[0] == "t_ms,source,kind,x,y,z,value"
    assert lines[1] == "0,apple_watch,event,,,,session_start"
    (tmp_path / "s1.csv").write_text("\n".join(lines) + "\n")
    df = load_session_csv(tmp_path / "s1.csv")
    acc = df[df["kind"] == "acc"]
    assert len(acc) == 300 and acc["t_ms"].iloc[0] == 0 and acc["t_ms"].iloc[-1] == 2990
    assert acc["y"].iloc[0] == pytest.approx(-9.81)  # G -> m/s², gravity kept
    gyro = df[df["kind"] == "gyro"]
    assert gyro["x"].iloc[-1] == pytest.approx(0.1)  # rad/s unchanged
    assert set(df["kind"]) == {"event", "acc", "gyro"}  # no hr, no location
    assert "42.38" not in "\n".join(lines)
    assert meta["started_at"] == "2026-10-27T16:11:17.313Z"  # UTC, milliseconds
    assert meta["placement"] == "ankle" and meta["sources"][0]["id"] == "apple_watch"
    assert meta["sources"][0]["sample_rate_hz"] == pytest.approx(100, abs=0.5)
    json.dumps(meta)


def test_repeated_samples_are_dropped():
    df = sensorlog_frame(10)
    df.loc[5, ACC_T] = df.loc[4, ACC_T]  # SensorLog repeats a sample when a stream lags
    lines, _ = convert(df, placement="ankle")
    assert sum(",acc," in line for line in lines) == 9


def test_not_a_sensorlog_file():
    with pytest.raises(ValueError, match="not a SensorLog"):
        convert(pd.DataFrame({"a": [1]}), placement="ankle")
