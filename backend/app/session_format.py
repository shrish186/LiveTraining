"""Validation and summary of session files. Spec: docs/session-format.md.

Pure functions, no I/O beyond reading the text stream you pass in.
"""

import csv
import math
import uuid
from dataclasses import dataclass, field
from datetime import UTC, datetime
from typing import Any, Iterable, TextIO

HEADER = ["t_ms", "source", "kind", "x", "y", "z", "value"]
SOURCES = {"phone", "whoop_hr", "apple_watch", "movesense", "xiao", "polar"}
KINDS = {"acc", "gyro", "hr", "rr", "event"}
VECTOR_KINDS = {"acc", "gyro"}
SCALAR_KINDS = {"hr", "rr"}
MAX_ERRORS = 20


class SessionFormatError(ValueError):
    def __init__(self, errors: list[str]):
        super().__init__("; ".join(errors))
        self.errors = errors


@dataclass
class CsvSummary:
    duration_ms: int = 0
    sample_count: int = 0  # every non-event row
    row_count: int = 0
    sources: list[str] = field(default_factory=list)
    hr_min: float | None = None
    hr_max: float | None = None
    events: list[dict[str, Any]] = field(default_factory=list)


def _float(text: str) -> float | None:
    try:
        value = float(text)
    except ValueError:
        return None
    return value if math.isfinite(value) else None


def _check_row(row: list[str]) -> str | None:
    """Returns an error message for one data row, or None if it is valid."""
    if len(row) != len(HEADER):
        return f"expected {len(HEADER)} columns, got {len(row)}"
    t_ms, source, kind, x, y, z, value = row
    if not t_ms.isdigit():
        return f"t_ms must be a non-negative integer, got {t_ms!r}"
    if source not in SOURCES:
        return f"unknown source {source!r}"
    if kind not in KINDS:
        return f"unknown kind {kind!r}"
    if kind in VECTOR_KINDS:
        if any(_float(v) is None for v in (x, y, z)):
            return f"{kind} needs numeric x, y, z"
        if value:
            return f"{kind} must leave value empty"
    else:
        if x or y or z:
            return f"{kind} must leave x, y, z empty"
        if kind in SCALAR_KINDS:
            v = _float(value)
            if v is None or v <= 0:
                return f"{kind} needs a positive numeric value, got {value!r}"
        elif not value.strip():
            return "event needs a label in value"
    return None


def validate_and_summarize(lines: Iterable[str] | TextIO) -> CsvSummary:
    """Streams through the CSV once. Raises SessionFormatError listing up to MAX_ERRORS problems."""
    reader = csv.reader(lines)
    errors: list[str] = []
    header = next(reader, None)
    if header is None:
        raise SessionFormatError(["file is empty"])
    if [h.strip() for h in header] != HEADER:
        raise SessionFormatError([f"header must be exactly {','.join(HEADER)}, got {','.join(header)}"])

    summary = CsvSummary()
    sources: set[str] = set()
    t_min: int | None = None
    t_max = 0
    for line_no, row in enumerate(reader, start=2):
        if not row:
            continue  # tolerate a trailing blank line
        problem = _check_row(row)
        if problem:
            errors.append(f"line {line_no}: {problem}")
            if len(errors) >= MAX_ERRORS:
                errors.append("too many errors, stopped")
                break
            continue
        t_ms, source, kind, _, _, _, value = row
        t = int(t_ms)
        t_min = t if t_min is None else min(t_min, t)
        t_max = max(t_max, t)
        summary.row_count += 1
        if kind == "event":
            summary.events.append({"t_ms": t, "label": value})
            continue
        summary.sample_count += 1
        sources.add(source)
        if kind == "hr":
            hr = float(value)
            summary.hr_min = hr if summary.hr_min is None else min(summary.hr_min, hr)
            summary.hr_max = hr if summary.hr_max is None else max(summary.hr_max, hr)

    if errors:
        raise SessionFormatError(errors)
    if summary.sample_count == 0:
        raise SessionFormatError(["no samples in file"])
    summary.duration_ms = t_max - (t_min or 0)
    summary.sources = sorted(sources)
    return summary


REQUIRED_METADATA = ("session_id", "sport", "session_type", "started_at")


def parse_started_at(text: str) -> datetime:
    """ISO 8601 -> naive UTC datetime. A string without an offset is taken as UTC."""
    dt = datetime.fromisoformat(text.replace("Z", "+00:00"))
    if dt.tzinfo is not None:
        dt = dt.astimezone(UTC).replace(tzinfo=None)
    return dt


def validate_metadata(meta: Any) -> dict[str, Any]:
    """Checks required fields and types. Returns the metadata with session_id normalised."""
    if not isinstance(meta, dict):
        raise SessionFormatError(["metadata must be a JSON object"])
    errors = [f"metadata.{k} is required" for k in REQUIRED_METADATA if not meta.get(k)]
    if errors:
        raise SessionFormatError(errors)
    try:
        meta["session_id"] = str(uuid.UUID(str(meta["session_id"])))
    except ValueError:
        errors.append("metadata.session_id must be a UUID")
    try:
        parse_started_at(str(meta["started_at"]))
    except ValueError:
        errors.append("metadata.started_at must be ISO 8601")
    for key in ("sport", "session_type"):
        if not isinstance(meta[key], str):
            errors.append(f"metadata.{key} must be a string")
    athlete_id = meta.get("athlete_id")
    if athlete_id is not None and (isinstance(athlete_id, bool) or not isinstance(athlete_id, int)):
        errors.append("metadata.athlete_id must be an integer or null")
    if not isinstance(meta.get("sources", []), list):
        errors.append("metadata.sources must be a list")
    if errors:
        raise SessionFormatError(errors)
    return meta
