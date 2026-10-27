import json
import sys
from pathlib import Path

import pytest

import analyze_session
import make_synthetic_session


@pytest.fixture(scope="module")
def synthetic(tmp_path_factory):
    out = tmp_path_factory.mktemp("synthetic")
    rows, meta = make_synthetic_session.generate(rate_hz=25, seed=3)
    (out / "s.csv").write_text("\n".join(rows) + "\n")
    (out / "s.json").write_text(json.dumps(meta))
    return out


def test_synthetic_session_analysis_finds_efforts_and_fatigue(synthetic):
    r = analyze_session.analyze(synthetic / "s.csv", synthetic / "s.json")
    assert r["profile"]["name"] == "soccer"  # picked from metadata sport
    assert len(r["efforts"]) == 6
    expected = [start for start, _, _ in make_synthetic_session.EFFORTS]
    assert [e.start_s for e in r["efforts"]] == pytest.approx(expected, abs=2.0)
    assert [e.fatigue for e in r["efforts"]] == [False, False, False, False, True, True]
    assert r["fatigue"].first_flagged is r["efforts"][4]
    assert "Fatigue building from 24:00" in analyze_session.summary_text(r)


def test_plot_is_written(synthetic):
    r = analyze_session.analyze(synthetic / "s.csv", synthetic / "s.json", "general")
    analyze_session.plot(r, synthetic / "s.png")
    assert (synthetic / "s.png").stat().st_size > 10_000


def test_synthetic_csv_passes_backend_validation(synthetic):
    """The backend validator is the reference implementation of docs/session-format.md."""
    backend = Path(__file__).resolve().parents[2] / "backend"
    sys.path.insert(0, str(backend))
    try:
        from app.session_format import validate_and_summarize, validate_metadata
    except ImportError:
        pytest.skip("backend not importable")
    finally:
        sys.path.remove(str(backend))
    with open(synthetic / "s.csv") as f:
        summary = validate_and_summarize(f)
    assert summary.sources == ["phone", "whoop_hr"]
    assert {e["label"] for e in summary.events} >= {"sync_jumps", "drill_start"}
    validate_metadata(json.loads((synthetic / "s.json").read_text()))
