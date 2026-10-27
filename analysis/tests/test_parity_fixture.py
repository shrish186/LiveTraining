import gzip
import json

import make_parity_fixture as fx


def test_parity_fixture_matches_current_analysis(tmp_path):
    """If the analysis logic changes, regenerate: python make_parity_fixture.py
    (then mobile/test/coach_parity_test.dart checks the app's live coach still agrees)."""
    assert fx.CSV_GZ.exists() and fx.EXPECTED.exists(), "run: python make_parity_fixture.py"
    csv = tmp_path / "s.csv"
    csv.write_text(gzip.open(fx.CSV_GZ, "rt").read())
    _, meta = fx.fixture_rows()
    (tmp_path / "s.json").write_text(json.dumps(meta))
    assert fx.expected_from(csv, tmp_path / "s.json") == json.loads(fx.EXPECTED.read_text())
