"""Writes the fixture that keeps the app's live coach in step with this analysis.

Usage: python make_parity_fixture.py

Outputs (both committed):
  mobile/test/fixtures/parity_session.csv.gz   synthetic session (acc + hr + events, 20 Hz)
  mobile/test/fixtures/parity_expected.json    what analyze_session.py finds in it

mobile/test/coach_parity_test.dart replays the CSV through LiveCoach and must reach the same
efforts, HR recoveries and fatigue flags. tests/test_parity_fixture.py fails if the expected JSON
no longer matches this analysis, so a logic change here forces a re-check on the app side.
"""

import gzip
import json
from pathlib import Path

import make_synthetic_session
from analyze_session import analyze

ROOT = Path(__file__).resolve().parent
FIXTURES = ROOT.parent / "mobile" / "test" / "fixtures"
CSV_GZ = FIXTURES / "parity_session.csv.gz"
EXPECTED = FIXTURES / "parity_expected.json"


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
    print(f"wrote {CSV_GZ} ({len(rows) - 1} rows) and {EXPECTED}: {len(expected['efforts'])} efforts, "
          f"fatigue on {[i + 1 for i, e in enumerate(expected['efforts']) if e['fatigue']]}")


if __name__ == "__main__":
    main()
