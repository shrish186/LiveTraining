"""Analyse a recorded session: efforts, HR recovery, fatigue, and a plot.

Usage: python analyze_session.py <csv> [--metadata <json>] [--profile <name>] [--out <png>]

The sport profile defaults to the metadata's `sport` if a profile with that name exists,
otherwise `general`. Thresholds and durations all come from profiles/sport_profiles.yaml.
"""

import argparse
import sys
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402

from ltlib import core  # noqa: E402
from ltlib.profiles import BASE_PROFILE, effort_params, get_profile, load_profiles  # noqa: E402
from ltlib.session_io import (  # noqa: E402
    event_rows,
    load_metadata,
    load_session_csv,
    motion_rows,
    pick_source,
    scalar_rows,
)


def mmss(t_s: float) -> str:
    return f"{int(t_s // 60):02d}:{int(t_s % 60):02d}"


def analyze(csv_path: str | Path, metadata_path: str | Path | None = None, profile_name: str | None = None) -> dict:
    df = load_session_csv(csv_path)
    meta = load_metadata(metadata_path)
    if profile_name is None:
        sport = meta.get("sport")
        profile_name = sport if sport in load_profiles() else BASE_PROFILE
    profile = get_profile(profile_name)
    placement = meta.get("placement")
    effort_cfg = effort_params(profile, placement)
    fatigue_cfg = profile["fatigue"]

    # Body-worn sensor over the phone; WHOOP heart rate over watch heart rate (merged sessions name them).
    motion_source = pick_source(df, "acc", meta.get("motion_source"), avoid=("phone",))
    hr_source = pick_source(df, "hr", meta.get("hr_source") or "whoop_hr")
    acc = motion_rows(df, "acc", motion_source)
    mag = core.smooth_on_grid(acc["t_s"].to_numpy(),
                              core.dynamic_magnitude(acc["x"].to_numpy(), acc["y"].to_numpy(), acc["z"].to_numpy()),
                              profile["motion"]["smoothing_window_s"])
    efforts = core.detect_efforts(mag, effort_cfg["threshold"], effort_cfg["min_duration_s"],
                                  effort_cfg.get("merge_gap_s", 0.0))
    hr = scalar_rows(df, "hr", hr_source)
    core.add_hr_recovery(efforts, hr["t_s"].to_numpy(), hr["value"].to_numpy(), fatigue_cfg["hr_recovery_window_s"])
    fatigue = core.assess_fatigue(efforts, fatigue_cfg["baseline_window_min"] * 60, fatigue_cfg["peak_drop_pct"])
    return {"df": df, "meta": meta, "profile": profile, "placement": placement, "effort_cfg": effort_cfg,
            "motion_source": motion_source, "hr_source": hr_source,
            "mag": mag, "hr": hr, "events": event_rows(df), "efforts": efforts, "fatigue": fatigue,
            "duration_s": float(df["t_ms"].max() - df["t_ms"].min()) / 1000.0, "load": core.motion_load(mag)}


def summary_text(r: dict) -> str:
    meta, hr, f = r["meta"], r["hr"], r["fatigue"]
    window = r["profile"]["fatigue"]["hr_recovery_window_s"]
    lines = [
        f"Session   {meta.get('session_id', '?')}",
        f"Sport     {meta.get('sport', '?')} / {meta.get('session_type', '?')}   placement: {r['placement'] or '?'}",
        f"Sources   motion: {r['motion_source'] or 'none'}   heart rate: {r['hr_source'] or 'none'}",
        f"Profile   {r['profile']['name']}   effort threshold {r['effort_cfg']['threshold']} m/s², "
        f"min {r['effort_cfg']['min_duration_s']} s",
        f"Duration  {mmss(r['duration_s'])}   motion load {r['load']:.1f} (m/s²)·min",
    ]
    if not hr.empty:
        lines.append(f"HR        min {hr['value'].min():.0f}  max {hr['value'].max():.0f}  "
                     f"mean {hr['value'].mean():.0f} bpm")
    lines += ["", f"Efforts: {len(r['efforts'])}",
              f"  #  start  dur(s)  peak   vs early   HR drop {window}s  flag"]
    for i, e in enumerate(r["efforts"], 1):
        drop = f"{-e.peak_drop_pct:+5.1f}%" if e.peak_drop_pct is not None else "  base"
        hrr = f"{e.hr_recovery_bpm:5.1f} bpm" if e.hr_recovery_bpm is not None else "    n/a  "
        flag = "FATIGUE" if e.fatigue else ("; ".join(e.notes) if e.notes else "")
        lines.append(f"  {i:<2} {mmss(e.start_s)}  {e.duration_s:5.1f}  {e.peak:5.2f}  {drop:>8}   {hrr:>10}  {flag}")
    lines.append("")
    if f.baseline_peak is None:
        lines.append("Fatigue: no efforts in the early baseline window, can't assess.")
    else:
        base_hrr = f"{f.baseline_hr_recovery:.1f} bpm" if f.baseline_hr_recovery is not None else "n/a"
        lines.append(f"Early baseline: peak {f.baseline_peak:.2f} m/s², HR drop {base_hrr}")
        if f.first_flagged:
            e = f.first_flagged
            lines.append(f"Fatigue building from {mmss(e.start_s)}: effort peak {e.peak_drop_pct:.1f}% below early "
                         f"efforts and HR recovery slower ({e.hr_recovery_bpm:.1f} vs {base_hrr}).")
        else:
            lines.append("No fatigue signal: effort peaks and HR recovery held up.")
    return "\n".join(lines)


def group_events(events: list[tuple[float, str]], min_gap_s: float) -> list[tuple[float, str]]:
    """Joins labels of events closer than min_gap_s so plot labels don't overprint."""
    groups: list[tuple[float, str]] = []
    for t, label in events:
        if groups and t - groups[-1][0] < min_gap_s:
            groups[-1] = (groups[-1][0], f"{groups[-1][1]}, {label}")
        else:
            groups.append((t, label))
    return groups


def plot(r: dict, out_png: str | Path) -> None:
    fig, (ax_hr, ax_m) = plt.subplots(2, 1, figsize=(12, 6.5), sharex=True, gridspec_kw={"height_ratios": [1, 1]})
    for ax in (ax_hr, ax_m):
        for e in r["efforts"]:
            ax.axvspan(e.start_s / 60, e.end_s / 60, color="#d9480f" if e.fatigue else "#1c7ed6",
                       alpha=0.18, lw=0)
        for t, label in r["events"]:
            ax.axvline(t / 60, color="#868e96", lw=0.8, ls="--")
    if not r["hr"].empty:
        ax_hr.plot(r["hr"]["t_s"] / 60, r["hr"]["value"], color="#c92a2a", lw=1.2)
    ax_hr.set_ylabel("Heart rate (bpm)")
    ax_hr.set_title(f"{r['meta'].get('sport', 'session')} · {r['meta'].get('session_type', '')} · "
                    f"profile {r['profile']['name']}", loc="left")
    ax_m.plot(r["mag"].index / 60, r["mag"].to_numpy(), color="#343a40", lw=0.8)
    ax_m.axhline(r["effort_cfg"]["threshold"], color="#1c7ed6", lw=1, ls=":", label="effort threshold")
    ax_m.set_ylabel("Motion magnitude (m/s²)")
    ax_m.set_xlabel("Time (min)")
    ymax = ax_m.get_ylim()[1]
    for t, label in group_events(r["events"], min_gap_s=r["duration_s"] * 0.02):
        ax_m.text(t / 60, ymax, f" {label}", rotation=90, va="top", ha="left", fontsize=7, color="#495057")
    from matplotlib.patches import Patch

    ax_m.legend(handles=[Patch(color="#1c7ed6", alpha=0.3, label="effort"),
                         Patch(color="#d9480f", alpha=0.3, label="effort, fatigue building"),
                         plt.Line2D([], [], color="#1c7ed6", ls=":", label="effort threshold")],
                loc="center right", fontsize=8, frameon=False)
    for ax in (ax_hr, ax_m):
        ax.spines[["top", "right"]].set_visible(False)
        ax.grid(axis="y", alpha=0.25)
    fig.tight_layout()
    fig.savefig(out_png, dpi=130)
    plt.close(fig)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("csv")
    parser.add_argument("--metadata", help="session metadata JSON (default: <csv>.json if it exists)")
    parser.add_argument("--profile", help="sport profile name (default: from metadata sport, else general)")
    parser.add_argument("--out", help="PNG path (default: <csv basename>.png)")
    args = parser.parse_args()

    csv_path = Path(args.csv)
    metadata = args.metadata
    if metadata is None and csv_path.with_suffix(".json").exists():
        metadata = csv_path.with_suffix(".json")
    try:
        result = analyze(csv_path, metadata, args.profile)
    except (KeyError, ValueError) as exc:
        sys.exit(f"error: {exc}")
    print(summary_text(result))
    out_png = Path(args.out) if args.out else csv_path.with_suffix(".png")
    plot(result, out_png)
    print(f"\nPlot: {out_png}")


if __name__ == "__main__":
    main()
