import numpy as np

from ltlib.actions import action_drift, detect_actions
from ltlib.steps import Strike, detect_strikes

CFG = dict(min_peak_g=8.0, min_ratio=1.4, runup_window_s=6.0, min_runup_strikes=4, min_gap_s=15.0, max_stride_s=1.5)


def spell(spikes: list[float], runup_g: float = 5.0, stride_s: float = 0.65, start: float = 10.0) -> list[Strike]:
    """Run-up strikes, a landing spike, two follow-through strides, then a slow walk back."""
    out: list[Strike] = []
    t = start
    for spike in spikes:
        out += [Strike(t + i * stride_s, runup_g) for i in range(8)]
        t += 8 * stride_s
        out.append(Strike(t, spike))
        out += [Strike(t + 0.6, 6.0), Strike(t + 1.2, 4.0)]
        out += [Strike(t + 3 + i * 1.1, 2.5) for i in range(20)]   # walking back to the mark
        t += 3 + 20 * 1.1 + 10
    return out


def test_counts_each_delivery_once():
    actions = detect_actions(spell([14, 15, 13, 14, 16, 14]), **CFG)
    assert len(actions) == 6
    assert all(a.runup_strikes >= 4 and abs(a.runup_stride_ms - 650) < 1 for a in actions)
    assert [round(a.peak_g) for a in actions] == [14, 15, 13, 14, 16, 14]


def test_sprint_without_a_spike_is_not_an_action():
    sprint = [Strike(5 + i * 0.6, 12.0 + (i % 3)) for i in range(20)]   # hard strides, all alike
    assert detect_actions(sprint, **CFG) == []


def test_big_hit_without_a_run_up_is_not_an_action():
    standing = [Strike(5.0, 2.0), Strike(20.0, 15.0)]                    # e.g. stamping or a stumble
    assert detect_actions(standing, **CFG) == []


def test_drift_shows_softer_landings_late_in_the_spell():
    actions = detect_actions(spell([15, 15, 15, 12, 12, 12]), **CFG)
    d = action_drift(actions, 3)
    assert d is not None and round(d.peak_g_pct) == -20 and abs(d.runup_stride_ms) < 1e-6
    assert action_drift(actions, 4) is None


def test_from_a_raw_signal():
    fs = 100
    t = np.arange(0, 60, 1 / fs)
    g = np.ones_like(t)
    def bump(at, height):
        g[:] += (height - 1) * np.exp(-((t - at) / 0.012) ** 2)
    for i in range(8):
        bump(10 + i * 0.65, 5.0)
    bump(10 + 8 * 0.65, 14.0)
    bump(10 + 8 * 0.65 + 0.6, 6.0)
    strikes = detect_strikes(t, g, 2.0, 0.35)
    actions = detect_actions(strikes, **CFG)
    assert len(actions) == 1 and abs(actions[0].t_s - 15.2) < 0.02 and actions[0].peak_g > 13.5


def test_cricket_session_end_to_end(tmp_path):
    import json

    import analyze_session

    fs, g0 = 100, 9.81
    t = np.arange(0, 400, 1 / fs)
    g = np.ones_like(t)

    def bump(at, height):
        near = np.abs(t - at) < 0.1
        g[near] += (height - 1) * np.exp(-((t[near] - at) / 0.012) ** 2)

    starts = [20 + 50 * k for k in range(7)]
    for k, s0 in enumerate(starts):
        for i in range(8):
            bump(s0 + i * 0.65, 5.0)
        bump(s0 + 8 * 0.65, 15.0 if k < 3 else 12.0)   # softer front-foot landings late in the spell
        bump(s0 + 8 * 0.65 + 0.6, 6.0)
    rows = ["t_ms,source,kind,x,y,z,value"] + [f"{int(round(ti * 1000))},xiao,acc,0,{gi * g0:.4f},0," for ti, gi in zip(t, g)]
    (tmp_path / "s.csv").write_text("\n".join(rows) + "\n")
    meta = {"format_version": 1, "session_id": "c", "sport": "cricket", "session_type": "training",
            "started_at": "2026-11-11T10:00:00Z", "placement": "ankle",
            "sources": [{"id": "xiao", "kinds": ["acc"], "sample_rate_hz": fs}]}
    (tmp_path / "s.json").write_text(json.dumps(meta))
    r = analyze_session.analyze(tmp_path / "s.csv", tmp_path / "s.json")
    acts = r["steps"]["actions"]
    assert acts["label_plural"] == "deliveries" and len(acts["actions"]) == 7
    assert acts["drift"] is None                     # 7 < 2 x 6: not enough for a drift
    text = analyze_session.summary_text(r)
    assert "Deliveries: 7" in text
