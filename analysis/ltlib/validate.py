"""Scores effort detection against efforts the athlete marked by hand, and sweeps the threshold.

A mark counts for a detected effort when it falls between `before_s` before the effort starts and
`after_s` after it ends (athletes tap Mark during or just after the effort). Each mark and each
effort is used at most once.
"""

from dataclasses import dataclass

import numpy as np
import pandas as pd

from ltlib.core import Effort, detect_efforts


@dataclass
class Score:
    threshold: float
    matched: list[tuple[float, Effort]]  # (mark time, effort)
    missed_marks: list[float]            # marked, not detected
    extra_efforts: list[Effort]          # detected, not marked

    @property
    def precision(self) -> float | None:
        n = len(self.matched) + len(self.extra_efforts)
        return len(self.matched) / n if n else None

    @property
    def recall(self) -> float | None:
        n = len(self.matched) + len(self.missed_marks)
        return len(self.matched) / n if n else None

    @property
    def f1(self) -> float:
        p, r = self.precision, self.recall
        return 0.0 if not p or not r else 2 * p * r / (p + r)


def match(marks: list[float], efforts: list[Effort], threshold: float,
          before_s: float = 5.0, after_s: float = 15.0) -> Score:
    """Greedy in time order: each mark takes the earliest unused effort whose window contains it."""
    used: set[int] = set()
    matched, missed = [], []
    for m in sorted(marks):
        hit = next((i for i, e in enumerate(efforts)
                    if i not in used and e.start_s - before_s <= m <= e.end_s + after_s), None)
        if hit is None:
            missed.append(m)
        else:
            used.add(hit)
            matched.append((m, efforts[hit]))
    extra = [e for i, e in enumerate(efforts) if i not in used]
    return Score(threshold, matched, missed, extra)


def sweep(mag: pd.Series, marks: list[float], thresholds: np.ndarray, min_duration_s: float,
          merge_gap_s: float, before_s: float = 5.0, after_s: float = 15.0) -> list[Score]:
    return [match(marks, detect_efforts(mag, float(t), min_duration_s, merge_gap_s), float(t), before_s, after_s)
            for t in thresholds]


def suggest(scores: list[Score], current: float) -> Score | None:
    """Best F1; among equals, the threshold in the middle of the best band (least sensitive to noise),
    then the one closest to the current setting. None if nothing was marked."""
    if not scores or scores[0].recall is None:
        return None
    best = max(s.f1 for s in scores)
    # Runs of consecutive thresholds that all reach the best F1.
    runs: list[list[int]] = []
    for i, s in enumerate(scores):
        if abs(s.f1 - best) > 1e-9:
            continue
        if runs and runs[-1][-1] == i - 1:
            runs[-1].append(i)
        else:
            runs.append([i])
    longest = max(len(r) for r in runs)
    candidates = [scores[r[len(r) // 2]] for r in runs if len(r) == longest]
    return min(candidates, key=lambda s: abs(s.threshold - current))
