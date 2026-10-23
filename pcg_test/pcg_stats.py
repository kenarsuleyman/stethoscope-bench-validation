"""Statistics for the heart-sound playback test (advisor's review, R8), from results/pcg_per_clip.csv.

- decision consistency as counts over clip x run pairs, with Wilson 95 % confidence intervals
- segment-level consistency: segments whose class equals the played class in all 3 runs (n = 47)
- exact McNemar test at segment level (majority class over the 3 runs) between two variants
- sensitivity / specificity against the true labels (label_true): played clip, and per run (mean of runs)
- transition table, one row per segment, for the supplementary material

Writes results/pcg_stats.csv, results/pcg_transitions.csv; prints a summary.
Usage:  python pcg_test/pcg_stats.py [--variants steth steth_eq sim_H ...]
"""

import argparse
import csv
from math import comb, sqrt
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
T = 0.5


def wilson(k, n, z=1.959964):
    p = k / n
    d = 1 + z * z / n
    c = (p + z * z / (2 * n)) / d
    h = z * sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / d
    return c - h, c + h


def mcnemar_exact(b, c):
    """Two-sided exact McNemar (binomial on the discordant pairs)."""
    n = b + c
    if n == 0:
        return 1.0
    k = min(b, c)
    p = 2 * sum(comb(n, i) for i in range(k + 1)) / 2 ** n
    return min(1.0, p)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--variants", nargs="+",
                    default=["steth", "steth_app", "steth_eq", "steth_eqlow", "steth_eqmid", "sim_H", "sim_Hn"])
    ap.add_argument("--compare", nargs=2, default=["steth", "steth_eq"])
    ap.add_argument("--results", type=Path, default=HERE / "results")
    a = ap.parse_args()

    rows = list(csv.DictReader(open(a.results / "pcg_per_clip.csv", encoding="utf-8")))
    y = np.array([int(r["label"]) for r in rows])            # label = label_true (pcg_model_compare)
    played = np.array([float(r["p_played"]) >= T for r in rows])
    runs = {v: np.array([[float(p) >= T for p in r[f"p_{v}_runs"].split(";")] for r in rows]) for v in a.variants}
    nseg, nrun = len(rows), next(iter(runs.values())).shape[1]

    def sens_spec(cls):
        tp = np.sum(cls & (y == 1)); fn = np.sum(~cls & (y == 1))
        tn = np.sum(~cls & (y == 0)); fp = np.sum(cls & (y == 0))
        return tp, fn, tn, fp

    out = []
    tp, fn, tn, fp = sens_spec(played)
    out.append({"variant": "played", "agree_k": "", "agree_n": "", "agree_pct": "", "ci_lo": "", "ci_hi": "",
                "seg_all_runs": "", "sens": f"{tp}/{tp + fn}", "spec": f"{tn}/{tn + fp}",
                "sens_pct": 100 * tp / (tp + fn), "spec_pct": 100 * tn / (tn + fp)})
    print(f"played clips: sensitivity {tp}/{tp + fn} = {100 * tp / (tp + fn):.1f} %, "
          f"specificity {tn}/{tn + fp} = {100 * tn / (tn + fp):.1f} %, accuracy {tp + tn}/{nseg}")
    for v, c in runs.items():
        same = c == played[:, None]
        k, n = int(same.sum()), same.size
        lo, hi = wilson(k, n)
        seg_all = int(np.all(same, axis=1).sum())
        tps = [sens_spec(c[:, i]) for i in range(nrun)]
        se = np.mean([t[0] / (t[0] + t[1]) for t in tps]); sp = np.mean([t[2] / (t[2] + t[3]) for t in tps])
        out.append({"variant": v, "agree_k": k, "agree_n": n, "agree_pct": 100 * k / n, "ci_lo": 100 * lo,
                    "ci_hi": 100 * hi, "seg_all_runs": seg_all,
                    "sens": ";".join(f"{t[0]}/{t[0] + t[1]}" for t in tps),
                    "spec": ";".join(f"{t[2]}/{t[2] + t[3]}" for t in tps), "sens_pct": 100 * se, "spec_pct": 100 * sp})
        print(f"{v:12s} consistency {k}/{n} = {100 * k / n:5.1f} % [95 % CI {100 * lo:.1f}-{100 * hi:.1f}]  "
              f"segments consistent in all {nrun} runs: {seg_all}/{nseg}  "
              f"sensitivity {100 * se:.1f} %  specificity {100 * sp:.1f} % (mean of runs)")

    # McNemar at segment level: majority class over runs agrees with played?
    v1, v2 = a.compare
    m1 = (runs[v1].sum(axis=1) * 2 > nrun) == played
    m2 = (runs[v2].sum(axis=1) * 2 > nrun) == played
    b = int(np.sum(m1 & ~m2)); c = int(np.sum(~m1 & m2))
    print(f"McNemar (segment level, majority of {nrun} runs) {v1} vs {v2}: consistent {int(m1.sum())} vs "
          f"{int(m2.sum())} of {nseg}; discordant {b} / {c}; exact two-sided p = {mcnemar_exact(b, c):.4f}")

    with open(a.results / "pcg_stats.csv", "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=list(out[0])); w.writeheader(); w.writerows(out)

    # transition table (supplementary material)
    with open(a.results / "pcg_transitions.csv", "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["file", "source", "label_true", "p_played", "class_played"]
                   + [f"p_{v}_runs" for v in a.variants] + [f"changed_{v}" for v in a.variants])
        for i, r in enumerate(rows):
            w.writerow([r["file"], r["source"], r["label"], f'{float(r["p_played"]):.3f}', int(played[i])]
                       + [r[f"p_{v}_runs"] for v in a.variants]
                       + [int(np.sum(runs[v][i] != played[i])) for v in a.variants])
    print("changed segments (runs with a class different from the played clip):")
    for i, r in enumerate(rows):
        ch = {v: int(np.sum(runs[v][i] != played[i])) for v in a.variants}
        if ch["steth"] or ch.get("steth_eq", 0):
            print(f'  {r["file"]:24s} {r["source"]:9s} y={r["label"]} played {float(r["p_played"]):.3f} | '
                  + " ".join(f"{v}:{n}" for v, n in ch.items()))


if __name__ == "__main__":
    main()
