"""Select the PCG clips for the playback test from the model's patient-wise TEST split.

Only PhysioNet/CinC 2016 and PASCAL Dataset-B (the datasets described in the thesis).
Per dataset and class, N patients are drawn at random (fixed seed) and one random 5 s
segment (4000 Hz, before bandpass/normalisation, as stored by the resample_segment stage)
is taken per patient, so no patient appears twice. Segments with more than
MAX_SILENCE_S of digital silence are skipped (another segment / patient is used). Clips are interleaved by dataset/class
so slow drifts during a run do not bias one group.

Output: pcg_test/clips/{normal,anormal}/*.wav + clips/filename_map.csv
        (columns: new, original, source, patient_id, label)

Usage:  python pcg_test/select_clips.py [--n 15] [--seed 2026]
"""

import argparse
import csv
import random
import shutil
from collections import defaultdict
from pathlib import Path

import numpy as np
import soundfile as sf

HERE = Path(__file__).resolve().parent
MEMS = HERE.parent.parent / "mems_python"
MAX_SILENCE_S = 0.2          # longest allowed run of digital zeros (|x| <= 1 LSB)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mems-root", type=Path, default=MEMS)
    ap.add_argument("--n", type=int, default=15)
    ap.add_argument("--seed", type=int, default=2026)
    ap.add_argument("--out", type=Path, default=HERE / "clips")
    a = ap.parse_args()

    meta = list(csv.DictReader(open(a.mems_root / "data" / "metadata.csv", encoding="utf-8")))
    pid2src = {m["patient_id"]: m["dataset_source"] for m in meta}
    test = list(csv.DictReader(open(a.mems_root / "splits" / "test.csv", encoding="utf-8")))

    groups = defaultdict(lambda: defaultdict(list))          # (source, label) -> patient -> stems
    for row in test:
        pid = row["patient_id"]
        # PASCAL-B patient ids in the split are the numeric recording prefix (e.g. "130")
        src = pid2src.get(pid, "pascal" if pid.isdigit() else "?")
        if src not in ("physionet", "pascal"):
            continue
        groups[(src, int(row["binary_label"]))][pid].append(Path(row["mel_path"]).stem)

    # Segments containing digital silence (zero padding / dropouts in the source file) are not
    # used: a real microphone can never reproduce exact zeros, so they would create an
    # original-vs-stethoscope difference that has nothing to do with the hardware.
    seg_dir = a.mems_root / "data" / "segments"

    def has_digital_silence(stem: str) -> bool:
        x, sr = sf.read(seg_dir / f"{stem}.wav")
        quiet = np.abs(x) <= 1.0 / 32768
        run = longest = 0
        for q in quiet:
            run = run + 1 if q else 0
            longest = max(longest, run)
        return longest > MAX_SILENCE_S * sr

    # PASCAL-B can label segments of one session differently (e.g. 190: normal and extrastole);
    # abnormal is drawn first and its patients are excluded from the normal pool.
    rng = random.Random(a.seed)
    picked = {}
    for key in sorted(groups, key=lambda k: (k[0], -k[1])):
        used = {p for p, _ in picked.get((key[0], 1 - key[1]), [])}
        pats = sorted(set(groups[key]) - used)
        rng.shuffle(pats)
        picked[key], n_sil = [], 0
        for p in pats:
            stems = sorted(groups[key][p])
            rng.shuffle(stems)
            ok = [s for s in stems if not has_digital_silence(s)]
            n_sil += len(stems) - len(ok)
            if ok:
                picked[key].append((p, ok[0]))
            if len(picked[key]) == a.n:
                break
        print(f"{key[0]:10s} label={key[1]}: {len(picked[key])} of {len(pats)} eligible test patients "
              f"({len(groups[key]) - len(pats)} excluded: picked in the other class; "
              f"{n_sil} segments skipped: digital silence)")

    order = [("physionet", 0), ("pascal", 1), ("pascal", 0), ("physionet", 1)]
    if a.out.exists():
        shutil.rmtree(a.out)
    rows, counter = [], {0: 0, 1: 0}
    for i in range(max(len(v) for v in picked.values())):
        for key in order:
            if i >= len(picked.get(key, [])):
                continue
            pid, stem = picked[key][i]
            lab = key[1]
            counter[lab] += 1
            cls = "anormal" if lab else "normal"
            new = f"{cls}/{cls}_{counter[lab]:03d}.wav"
            dst = a.out / new
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(a.mems_root / "data" / "segments" / f"{stem}.wav", dst)
            rows.append({"new": new, "original": f"{len(rows)+1:02d}_{key[0]}_{stem}.wav",
                         "source": key[0], "patient_id": pid, "label": lab})
    with open(a.out / "filename_map.csv", "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=list(rows[0]))
        w.writeheader()
        w.writerows(rows)
    print(f"{len(rows)} clips -> {a.out}")


if __name__ == "__main__":
    main()
