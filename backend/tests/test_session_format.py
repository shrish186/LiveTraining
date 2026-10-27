import io

import pytest

from app.session_format import SessionFormatError, validate_and_summarize, validate_metadata
from tests.conftest import GOOD_CSV, make_metadata

HEADER = "t_ms,source,kind,x,y,z,value\n"


def errors_for(text: str) -> list[str]:
    with pytest.raises(SessionFormatError) as exc:
        validate_and_summarize(io.StringIO(text))
    return exc.value.errors


def test_good_file_summary():
    s = validate_and_summarize(io.StringIO(GOOD_CSV))
    assert s.duration_ms == 15032
    assert s.sample_count == 6
    assert s.sources == ["phone", "whoop_hr"]
    assert (s.hr_min, s.hr_max) == (72, 151)
    assert s.events == [{"t_ms": 0, "label": "session_start"}, {"t_ms": 15032, "label": "sync_jumps"}]


def test_bad_header():
    errors = errors_for("time,source,kind,x,y,z,value\n0,phone,acc,1,2,3,\n")
    assert "header must be exactly" in errors[0]


def test_empty_file():
    assert errors_for("") == ["file is empty"]


def test_header_only_has_no_samples():
    assert errors_for(HEADER) == ["no samples in file"]


@pytest.mark.parametrize(
    "row, message",
    [
        ("-1,phone,acc,1,2,3,", "t_ms must be a non-negative integer"),
        ("1.5,phone,acc,1,2,3,", "t_ms must be a non-negative integer"),
        ("0,fitbit,acc,1,2,3,", "unknown source"),
        ("0,phone,temp,,,,3", "unknown kind"),
        ("0,phone,acc,1,2,,", "acc needs numeric x, y, z"),
        ("0,phone,gyro,1,abc,3,", "gyro needs numeric x, y, z"),
        ("0,phone,acc,1,2,3,9", "acc must leave value empty"),
        ("0,whoop_hr,hr,,,,", "hr needs a positive numeric value"),
        ("0,whoop_hr,hr,,,,-4", "hr needs a positive numeric value"),
        ("0,whoop_hr,rr,1,,,800", "rr must leave x, y, z empty"),
        ("0,phone,event,,,,", "event needs a label"),
        ("0,phone,acc,1,2,3", "expected 7 columns"),
        ("0,phone,acc,nan,2,3,", "acc needs numeric x, y, z"),
    ],
)
def test_bad_rows(row, message):
    errors = errors_for(HEADER + "0,phone,acc,1,2,3,\n" + row + "\n")
    assert len(errors) == 1
    assert errors[0].startswith("line 3:")
    assert message in errors[0]


def test_error_list_is_capped():
    errors = errors_for(HEADER + "0,bogus,acc,1,2,3,\n" * 100)
    assert len(errors) == 21
    assert errors[-1] == "too many errors, stopped"


def test_metadata_ok():
    meta = validate_metadata(make_metadata(session_id="4F6C2B0E-3F7A-4D2F-9F0E-6A1F5D2B7C11"))
    assert meta["session_id"] == "4f6c2b0e-3f7a-4d2f-9f0e-6a1f5d2b7c11"


@pytest.mark.parametrize(
    "overrides, message",
    [
        ({"sport": ""}, "metadata.sport is required"),
        ({"session_id": "nope"}, "must be a UUID"),
        ({"started_at": "yesterday"}, "must be ISO 8601"),
        ({"athlete_id": "7"}, "athlete_id must be an integer"),
        ({"sources": "phone"}, "sources must be a list"),
    ],
)
def test_metadata_errors(overrides, message):
    with pytest.raises(SessionFormatError) as exc:
        validate_metadata(make_metadata(**overrides))
    assert any(message in e for e in exc.value.errors)
