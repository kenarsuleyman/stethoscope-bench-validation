"""Dataset table and per-dataset test performance of the deployed TFLite model (paper Table 1 / 2.2).

Reads the mems_python CSV chain (labels corrected on 2026-10-21), runs the TFLite model on every test
Mel image (splits/test.csv) and writes
    results/dataset_table.csv          recordings, patients, segments (train/val/test) and class balance
    results/model_test_by_dataset.csv  accuracy, sensitivity, specificity, AUC per dataset and overall
    results/test_probs.csv             probability per test segment (for later reuse)
Usage:  python pcg_test/model_test_by_dataset.py [--model pcg_test/model/heart_sound_classifier_fp16.tflite]
"""

import argparse
import csv
import sys
from collections import Counter, defaultdict
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import predict_pcg as pp  # noqa: E402

MEMS = pp.DEFAULT_MEMS


def source_of(patient_id: str, pn_ids: set) -> str:
    if patient_id in pn_ids:
        return "physionet"
    for p in ("circor", "buet", "yaseen"):
        if patient_id.startswith(p + "_"):
            return p
    return "pascal"


def auc(y, s):
    o = np.argsort(s); r = np.empty(len(s)); r[o] = np.arange(1, len(s) + 1)
    n1 = y.sum(); n0 = len(y) - n1
    return float((r[y == 1].sum() - n1 * (n1 + 1) / 2) / (n1 * n0)) if n1 and n0 else float("nan")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", type=Path, default=pp.DEFAULT_MODEL)
    ap.add_argument("--out", type=Path, default=HERE / "results")
    a = ap.parse_args()

    meta = list(csv.DictReader(open(MEMS / "data" / "metadata.csv", encoding="utf-8")))
    pn_ids = {r["patient_id"] for r in meta if r["dataset_source"] == "physionet"}
    table = defaultdict(Counter)
    for r in meta:
        s = r["dataset_source"]
        table[s]["recordings"] += 1; table[s][f"rec_label{r['binary_label']}"] += 1
    splits = {}
    for sp in ("train", "val", "test"):
        rows = list(csv.DictReader(open(MEMS / "splits" / f"{sp}.csv", encoding="utf-8")))
        splits[sp] = rows
        for r in rows:
            s = source_of(r["patient_id"], pn_ids)
            table[s][f"seg_{sp}"] += 1; table[s][f"seg_{sp}_label{r['binary_label']}"] += 1
    # patients = groups used by the patient-wise split (PASCAL-B: subject number, 165 groups; PhysioNet: record id)
    pats = defaultdict(set)
    for rows in splits.values():
        for r in rows:
            pats[source_of(r["patient_id"], pn_ids)].add(r["patient_id"])
    for s in table:
        table[s]["patients"] = len(pats[s])
    order = ["physionet", "pascal", "circor", "buet", "yaseen"]
    out = a.out; out.mkdir(parents=True, exist_ok=True)
    cols = ["dataset", "recordings", "rec_normal", "rec_abnormal", "patients", "seg_train", "seg_val", "seg_test",
            "test_normal", "test_abnormal"]
    with open(out / "dataset_table.csv", "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f); w.writerow(cols)
        tot = Counter()
        for s in order:
            t = table[s]
            row = [s, t["recordings"], t["rec_label0"], t["rec_label1"], t["patients"], t["seg_train"], t["seg_val"],
                   t["seg_test"], t["seg_test_label0"], t["seg_test_label1"]]
            w.writerow(row); tot.update(dict(zip(cols[1:], row[1:])))
            print(row)
        w.writerow(["total"] + [tot[c] for c in cols[1:]]); print(["total"] + [tot[c] for c in cols[1:]])

    pw, _, _ = pp.load_pipeline(MEMS)
    backend = pp.load_tflite(a.model, pw)
    test = splits["test"]
    probs = np.zeros(len(test))
    batch = 64
    for i in range(0, len(test), batch):
        mels = [np.load(MEMS / r["mel_path"]).astype(np.float32) for r in test[i:i + batch]]
        probs[i:i + batch] = backend.predict_batch(mels)
    y = np.array([int(r["binary_label"]) for r in test]); src = np.array([source_of(r["patient_id"], pn_ids) for r in test])
    with open(out / "test_probs.csv", "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f); w.writerow(["mel_path", "dataset", "label", "p"])
        w.writerows([r["mel_path"], s, l, f"{p:.5f}"] for r, s, l, p in zip(test, src, y, probs))
    with open(out / "model_test_by_dataset.csv", "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f); w.writerow(["dataset", "n", "normal", "abnormal", "accuracy", "sensitivity", "specificity", "auc"])
        for s in order + ["all"]:
            m = np.ones(len(y), bool) if s == "all" else src == s
            c = probs[m] >= 0.5; t = y[m]
            se = np.sum(c & (t == 1)) / max(np.sum(t == 1), 1); sp = np.sum(~c & (t == 0)) / max(np.sum(t == 0), 1)
            acc = np.mean(c == t)
            w.writerow([s, m.sum(), int(np.sum(t == 0)), int(np.sum(t == 1)), f"{acc:.4f}", f"{se:.4f}", f"{sp:.4f}", f"{auc(t, probs[m]):.4f}"])
            print(f"{s:10s} n={m.sum():5d} acc {100 * acc:5.1f}  Se {100 * se:5.1f}  Sp {100 * sp:5.1f}  AUC {auc(t, probs[m]):.3f}")


if __name__ == "__main__":
    main()
