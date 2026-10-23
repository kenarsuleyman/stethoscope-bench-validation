"""Compare two probability CSVs written by predict_pcg.py (same file names).

Usage: python pcg_test/compare_probs.py A.csv B.csv [--map pcg_test/clips/filename_map.csv]
Prints accuracy of both against the labels, |p_A - p_B| statistics and class changes,
overall and per source/class.
"""

import argparse
import csv
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent


def read(p):
    return {r["file"]: float(r["p_mean"]) for r in csv.DictReader(open(p, encoding="utf-8"))}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("a", type=Path)
    ap.add_argument("b", type=Path)
    ap.add_argument("--map", type=Path, default=HERE / "clips" / "filename_map.csv")
    ap.add_argument("--threshold", type=float, default=0.5)
    x = ap.parse_args()
    A, B = read(x.a), read(x.b)
    M = {r["new"]: r for r in csv.DictReader(open(x.map, encoding="utf-8"))}
    keys = sorted(set(A) & set(B))
    t = x.threshold

    def report(name, ks):
        if not ks:
            return
        lab = np.array([M[k]["label"] == "1" for k in ks])
        pa, pb = np.array([A[k] for k in ks]), np.array([B[k] for k in ks])
        d = np.abs(pa - pb)
        print(f"{name:22s} n={len(ks):2d}  acc A={np.sum((pa >= t) == lab):2d}  acc B={np.sum((pb >= t) == lab):2d}  "
              f"same class={np.sum((pa >= t) == (pb >= t)):2d}  |dp| median={np.median(d):.3f} max={d.max():.3f}")

    report("all", keys)
    for s in ("physionet", "pascal"):
        for l, ln in (("0", "normal"), ("1", "abnormal")):
            report(f"{s} {ln}", [k for k in keys if M[k]["source"] == s and M[k]["label"] == l])
    flips = [k for k in keys if (A[k] >= t) != (B[k] >= t)]
    for k in flips:
        print(f"  class change: {k}  A={A[k]:.3f}  B={B[k]:.3f}  ({M[k]['original']})")


if __name__ == "__main__":
    main()
