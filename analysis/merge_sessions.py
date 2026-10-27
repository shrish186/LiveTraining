"""Merge a phone recording with a recording from a second device (e.g. the Apple Watch on the leg).

Usage: python merge_sessions.py <base.csv> <other.csv> [--out merged.csv] [--no-refine]

<base> is usually the phone session (it has WHOOP heart rate), <other> the watch session (motion).
Each CSV needs its .json metadata next to it. Writes <out>.csv + <out>.json; then run
analyze_session.py on the merged CSV. Do sync jumps at the start of both recordings for exact
alignment.
"""

import argparse
import json
import sys
from pathlib import Path

from ltlib.merge import merge_sessions
from ltlib.session_io import HEADER, format_float, load_metadata, load_session_csv


def _metadata_for(csv: Path) -> dict:
    meta = csv.with_suffix(".json")
    if not meta.exists():
        sys.exit(f"error: {meta} not found (every session CSV needs its .json metadata)")
    return load_metadata(meta)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("base")
    parser.add_argument("other")
    parser.add_argument("--out", help="output CSV (default: output/merged_<base id>.csv)")
    parser.add_argument("--no-refine", action="store_true", help="align by clock only, skip the sync-jump match")
    args = parser.parse_args()

    base, other = Path(args.base), Path(args.other)
    rows, meta, info = merge_sessions(load_session_csv(base), _metadata_for(base), load_session_csv(other),
                                      _metadata_for(other), refine=not args.no_refine)
    out = Path(args.out) if args.out else Path("output") / f"merged_{base.stem}.csv"
    out.parent.mkdir(parents=True, exist_ok=True)
    rows = rows[HEADER].astype({"t_ms": int})
    for axis in ("x", "y", "z"):  # same number format as the recorders (docs/session-format.md)
        rows[axis] = [format_float(v) if v == v else "" for v in rows[axis]]
    rows.to_csv(out, index=False, lineterminator="\n")
    out.with_suffix(".json").write_text(json.dumps(meta, indent=2) + "\n")

    how = (f"sync jumps (correlation {info.correlation})" if info.method == "sync_jumps"
           else "clock only (no clear sync-jump match)")
    print(f"Aligned by {how}: other recording shifted {info.offset_ms:+d} ms "
          f"(clock said {info.clock_offset_ms:+d} ms)")
    print(f"Motion from {meta['motion_source']}, heart rate from {meta['hr_source'] or 'whatever is present'}")
    print(f"Wrote {out} and {out.with_suffix('.json')}")
    print(f"Next: python analyze_session.py {out}")


if __name__ == "__main__":
    main()
