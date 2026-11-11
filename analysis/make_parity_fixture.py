"""Writes the fixture that keeps the app's live coach in step with this analysis.

Usage: python make_parity_fixture.py

Outputs (all committed):
  mobile/test/fixtures/parity_session.csv.gz   synthetic session (acc + hr + events, 20 Hz)
  mobile/test/fixtures/parity_expected.json    what analyze_session.py finds in it
  mobile/test/fixtures/spell_session.csv.gz    synthetic bowling spell from the leg sensor (104 Hz)
  mobile/test/fixtures/spell_expected.json     the deliveries analyze_session.py finds in it
  mobile/test/fixtures/jumps_signal.csv        a readiness check: 3 countermovement jumps (t_s, total g)
  mobile/test/fixtures/jumps_expected.json     the jumps ltlib.steps.detect_jumps finds in it

mobile/test/coach_parity_test.dart replays the CSV through LiveCoach and must reach the same
efforts, HR recoveries and fatigue flags. tests/test_parity_fixture.py fails if the expected JSON
no longer matches this analysis, so a logic change here forces a re-check on the app side.
"""

import gzip
import json
from pathlib import Path

import make_synthetic_session
import make_synthetic_spell
from analyze_session import analyze

ROOT = Path(__file__).resolve().parent
FIXTURES = ROOT.parent / "mobile" / "test" / "fixtures"
CSV_GZ = FIXTURES / "parity_session.csv.gz"
EXPECTED = FIXTURES / "parity_expected.json"
JUMPS_CSV = FIXTURES / "jumps_signal.csv"
JUMPS_EXPECTED = FIXTURES / "jumps_expected.json"
SPELL_GZ = FIXTURES / "spell_session.csv.gz"
SPELL_EXPECTED = FIXTURES / "spell_expected.json"


def jump_signal(seed: int = 4) -> tuple[list[float], list[float]]:
    """Standing still, then 3 countermovement jumps (flights 0.42, 0.48, 0.45 s) at 104 Hz, ankle-like g."""
    import numpy as np

    rng = np.random.default_rng(seed)
    fs = 104
    t = np.arange(0, 16, 1 / fs)
    g = 1 + rng.normal(0, 0.02, len(t))
    for start, flight in ((3.0, 0.42), (7.5, 0.48), (12.0, 0.45)):
        dip = (t >= start - 0.35) & (t < start - 0.15)
        g[dip] = 0.7                                   # countermovement
        push = (t >= start - 0.15) & (t < start)
        g[push] = 2.6 + 0.4 * np.sin((t[push] - start + 0.15) / 0.15 * np.pi)   # push-off
        air = (t >= start) & (t < start + flight)
        g[air] = 0.05 + rng.normal(0, 0.01, air.sum())  # flight: near free fall
        land = (t >= start + flight) & (t < start + flight + 0.08)
        g[land] = 4.5                                  # landing spike
        absorb = (t >= start + flight + 0.08) & (t < start + flight + 0.3)
        g[absorb] = 1.4
    return [round(float(x), 4) for x in t], [round(float(x), 4) for x in g]


def jumps_expected(t: list[float], g: list[float]) -> dict:
    import numpy as np

    from ltlib.profiles import get_profile
    from ltlib.steps import detect_jumps

    j = get_profile("general")["jumps"]
    found = detect_jumps(np.array(t), np.array(g), j["takeoff_g"], j["flight_below_g"], j["landing_above_g"],
                         j["landing_peak_g"], j["min_flight_s"], j["max_flight_s"], j["quiet_s"], j["quiet_std_g"])
    return {"jumps": [{"takeoff_s": round(x.takeoff_s, 4), "landing_s": round(x.landing_s, 4),
                       "height_cm": round(x.height_cm, 3)} for x in found]}


def spell_rows() -> tuple[list[str], dict]:
    rows, meta, _ = make_synthetic_spell.generate(overs=2, seed=5, warmup_s=40)
    return rows, meta


def spell_expected_from(csv_path: Path, meta_path: Path) -> dict:
    r = analyze(csv_path, meta_path)
    acts = r["steps"]["actions"]
    return {
        "profile": r["profile"]["name"],
        "placement": r["placement"],
        "strikes": len(r["steps"]["strikes"]),
        "deliveries": [{"t_s": round(a.t_s, 3), "peak_g": round(a.peak_g, 4), "runup_strikes": a.runup_strikes}
                       for a in acts["actions"]],
        "drift_pct": None if acts["drift"] is None else round(acts["drift"].peak_g_pct, 3),
    }


def fixture_rows() -> tuple[list[str], dict]:
    rows, meta = make_synthetic_session.generate(rate_hz=20, seed=11)
    keep = [rows[0]] + [r for r in rows[1:] if ",gyro," not in r and ",rr," not in r]  # smaller file
    return keep, meta


def expected_from(csv_path: Path, meta_path: Path) -> dict:
    r = analyze(csv_path, meta_path)
    return {
        "profile": r["profile"]["name"],
        "placement": r["placement"],
        "efforts": [
            {"start_s": round(e.start_s, 2), "end_s": round(e.end_s, 2), "peak": round(e.peak, 4),
             "hr_recovery_bpm": None if e.hr_recovery_bpm is None else round(e.hr_recovery_bpm, 2),
             "fatigue": e.fatigue}
            for e in r["efforts"]
        ],
    }


def main() -> None:
    import tempfile

    rows, meta = fixture_rows()
    FIXTURES.mkdir(parents=True, exist_ok=True)
    text = "\n".join(rows) + "\n"
    with gzip.open(CSV_GZ, "wt", newline="") as f:
        f.write(text)
    with tempfile.TemporaryDirectory() as tmp:
        csv, js = Path(tmp) / "s.csv", Path(tmp) / "s.json"
        csv.write_text(text)
        js.write_text(json.dumps(meta))
        expected = expected_from(csv, js)
    EXPECTED.write_text(json.dumps(expected, indent=2) + "\n")

    rows_s, meta_s = spell_rows()
    text_s = "\n".join(rows_s) + "\n"
    with gzip.open(SPELL_GZ, "wt", newline="") as f:
        f.write(text_s)
    with tempfile.TemporaryDirectory() as tmp:
        csv, js = Path(tmp) / "s.csv", Path(tmp) / "s.json"
        csv.write_text(text_s)
        js.write_text(json.dumps(meta_s))
        spell = spell_expected_from(csv, js)
    SPELL_EXPECTED.write_text(json.dumps(spell, indent=2) + "\n")
    jt, jg = jump_signal()
    JUMPS_CSV.write_text("t_s,g\n" + "".join(f"{a},{b}\n" for a, b in zip(jt, jg)))
    jumps = jumps_expected(jt, jg)
    JUMPS_EXPECTED.write_text(json.dumps(jumps, indent=2) + "\n")
    print(f"wrote {JUMPS_CSV}: {len(jumps['jumps'])} jumps")
    print(f"wrote {SPELL_GZ} ({len(rows_s) - 1} rows): {len(spell['deliveries'])} deliveries")
    print(f"wrote {CSV_GZ} ({len(rows) - 1} rows) and {EXPECTED}: {len(expected['efforts'])} efforts, "
          f"fatigue on {[i + 1 for i, e in enumerate(expected['efforts']) if e['fatigue']]}")


if __name__ == "__main__":
    main()
