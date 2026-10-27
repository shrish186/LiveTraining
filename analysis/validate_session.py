"""How well does effort detection match what really happened? Scores it against your own marks.

Usage: python validate_session.py <csv> [--metadata <json>] [--profile <name>] [--label mark]
                                  [--before 5] [--after 15]

Protocol: during the session tap Mark in the app right after each real hard effort (sprint, jump
set, interval). Tap nothing else with that label. This script then reports:
  - which marked efforts were detected, which were missed, and which detections had no mark
  - precision (detections that were real) and recall (real efforts that were detected)
  - the same at other thresholds, and a suggested threshold for this sport and placement

A mark matches a detected effort if it is between --before s before the effort starts and --after s
after it ends. Thresholds are only suggested: change profiles/sport_profiles.yaml yourself, and
check the suggestion holds over a few sessions before you do.
"""

import argparse
import sys
from pathlib import Path

import numpy as np

from analyze_session import analyze, mmss
from ltlib.validate import Score, suggest, sweep


def pct(v: float | None) -> str:
    return "  n/a" if v is None else f"{v * 100:4.0f}%"


def report(r: dict, label: str, before_s: float, after_s: float) -> str:
    marks = [t for t, l in r["events"] if l == label]
    cfg, placement = r["effort_cfg"], r["placement"]
    current = float(cfg["threshold"])
    lines = [f"Profile {r['profile']['name']}, placement {placement or '?'}: threshold {current} m/s², "
             f"min {cfg['min_duration_s']} s, merge gap {cfg.get('merge_gap_s', 0.0)} s",
             f"Marks labelled '{label}': {len(marks)}"]
    if not marks:
        lines.append(f"No '{label}' marks in this session. Tap Mark after each hard effort, then run again.")
        return "\n".join(lines)

    hi = max(current * 2, float(r["mag"].max()) if not r["mag"].empty else current)
    thresholds = np.round(np.arange(1.0, hi + 0.25, 0.25), 2)
    if current not in thresholds:
        thresholds = np.sort(np.append(thresholds, current))
    scores = sweep(r["mag"], marks, thresholds, cfg["min_duration_s"], cfg.get("merge_gap_s", 0.0),
                   before_s, after_s)
    now: Score = next(s for s in scores if s.threshold == current)

    lines += ["", f"At the current threshold ({current}):"]
    for m, e in now.matched:
        lines.append(f"  ok      mark {mmss(m)}  effort {mmss(e.start_s)}-{mmss(e.end_s)}  peak {e.peak:.1f}")
    for m in now.missed_marks:
        near = r["mag"].loc[max(0.0, m - 30):m + 5]
        peak = f"{near.max():.1f}" if not near.empty else "n/a"
        lines.append(f"  MISSED  mark {mmss(m)}  (highest motion in the 30 s before: {peak} m/s²)")
    for e in now.extra_efforts:
        lines.append(f"  EXTRA   effort {mmss(e.start_s)}-{mmss(e.end_s)}  peak {e.peak:.1f}, no mark")
    lines.append(f"  precision {pct(now.precision)}   recall {pct(now.recall)}   F1 {now.f1:.2f}")

    lines += ["", "  threshold  found  missed  extra  precision  recall    F1"]
    for s in scores:
        if s.f1 == 0 and s.threshold != current:
            continue
        mark = "  <- current" if s.threshold == current else ""
        lines.append(f"  {s.threshold:9.2f}  {len(s.matched):5d}  {len(s.missed_marks):6d}  {len(s.extra_efforts):5d}"
                     f"  {pct(s.precision):>9}  {pct(s.recall):>6}  {s.f1:4.2f}{mark}")

    best = suggest(scores, current)
    lines.append("")
    if best is None or best.f1 <= now.f1 + 1e-9:
        lines.append("The current threshold is as good as any on this session. No change suggested.")
    else:
        where = (f"profiles/sport_profiles.yaml › {r['profile']['name']} › placements › {placement} › threshold"
                 if placement else f"profiles/sport_profiles.yaml › {r['profile']['name']} › effort › threshold")
        lines.append(f"Suggested threshold {best.threshold} (F1 {best.f1:.2f} vs {now.f1:.2f} now). "
                     f"Set it in {where} once a few sessions agree.")
    if len(marks) < 6:
        lines.append(f"Only {len(marks)} marks: record more efforts before trusting a suggestion.")
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("csv")
    parser.add_argument("--metadata", help="session metadata JSON (default: <csv>.json if it exists)")
    parser.add_argument("--profile", help="sport profile name (default: from metadata sport, else general)")
    parser.add_argument("--label", default="mark", help="event label of your marks (default: mark)")
    parser.add_argument("--before", type=float, default=5.0, help="s a mark may come before an effort starts")
    parser.add_argument("--after", type=float, default=15.0, help="s a mark may come after an effort ends")
    args = parser.parse_args()

    csv_path = Path(args.csv)
    metadata = args.metadata
    if metadata is None and csv_path.with_suffix(".json").exists():
        metadata = csv_path.with_suffix(".json")
    try:
        result = analyze(csv_path, metadata, args.profile)
    except (KeyError, ValueError) as exc:
        sys.exit(f"error: {exc}")
    print(report(result, args.label, args.before, args.after))


if __name__ == "__main__":
    main()
