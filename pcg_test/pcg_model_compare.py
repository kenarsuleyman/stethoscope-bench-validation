"""Model-level comparison: played clips vs. stethoscope recordings, over several runs.

For each run folder (made by run_measurement(..., 'pcg') + analyze_pcg) the deployed model
is applied with the training pipeline (predict_pcg.py) to
  steth      aligned stethoscope clips, direct 44.1 kHz -> 4 kHz resampling (training code)
  steth_app  the same clips through the app's path (44.1 -> 16 kHz -> 4 kHz)
  steth_eq   clips corrected with the inverse tone-measured chain response
  steth_eqlow / steth_eqmid   correction applied only below / only from 100 Hz (pcg_forward_sim.m)
  sim_H      played clip filtered with the tone-measured response (ideal linear system, run-independent)
  sim_Hn     sim_H plus noise with the run's noise spectrum at the clip's measured band SNR
and compared with the clip as played (pcg_test/stimulus/played_ref) and the raw original.
Ground truth is the label_true column of clips/filename_map.csv (PhysioNet labels corrected on
2026-10-21; the "label" column and the normal_/anormal_ file names keep the old, inverted labels).
It also compares the model input images (log-mel, 224x224) of played vs. recorded clips.

Writes  pcg_test/results/pcg_per_clip.csv  (one row per clip, runs averaged)
        pcg_test/results/pcg_summary.csv   (agreement / accuracy per group and variant)
        <run>/probs_<variant>.csv          (per run)

Usage:  python pcg_test/pcg_model_compare.py data/<run1> data/<run2> data/<run3>
"""

import argparse
import csv
import sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import predict_pcg as pp  # noqa: E402

VARIANTS = {"steth": ("steth", False), "steth_app": ("steth", True), "steth_eq": ("steth_eq", False),
            "steth_eqlow": ("steth_eqlow", False), "steth_eqmid": ("steth_eqmid", False),
            "sim_H": ("sim_H", False), "sim_Hn": ("sim_Hn", False)}
SHARED = {"sim_H"}   # run-independent variants live in pcg_test/sim/<variant>/


def model_image(path, pw, design_bandpass, config, app_path=False):
    """First 5 s segment as the model sees it (224x224, one channel)."""
    prep, mel_cfg = config["preprocessing"], config["mel_spectrogram"]
    sr_t = prep["target_sr"]
    audio, sr = pw.load_audio_mono(path)
    if app_path and sr != pp.APP_CAPTURE_SR:
        audio, sr = pw.resample_to_target(audio, sr, pp.APP_CAPTURE_SR), pp.APP_CAPTURE_SR
    audio = pw.resample_to_target(audio, sr, sr_t)
    seg = pw.segment_audio(audio, sr_t * prep["segment_length_s"])[0]
    sos = design_bandpass(prep["bandpass_low"], prep["bandpass_high"], sr_t, prep["butterworth_order"])
    return pw.preprocess_segment(seg, sos, mel_cfg, sr_t, tuple(mel_cfg["image_size"]))[..., 0]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("runs", nargs="+", type=Path)
    ap.add_argument("--out", type=Path, default=HERE / "results")
    ap.add_argument("--threshold", type=float, default=0.5)
    ap.add_argument("--model", type=Path, default=pp.DEFAULT_MODEL)
    ap.add_argument("--probs-prefix", default="probs", help="per-run file name prefix (keep other models' files)")
    ap.add_argument("--variants", nargs="+", default=list(VARIANTS), choices=list(VARIANTS),
                    help="subset of variants (e.g. runs without pcg_forward_sim.m have no steth_eqlow / eqmid)")
    a = ap.parse_args()
    t = a.threshold
    variants = {v: VARIANTS[v] for v in a.variants}
    for v in ("steth", "steth_app", "steth_eq"):          # used by the per-clip progress line
        variants.setdefault(v, VARIANTS[v])

    pw, design_bandpass, config = pp.load_pipeline(pp.DEFAULT_MEMS)
    backend = pp.load_tflite(a.model, pw)
    clips = list(csv.DictReader(open(HERE / "clips" / "filename_map.csv", encoding="utf-8")))
    played_dir, orig_dir = HERE / "stimulus" / "played_ref", HERE / "clips"

    def prob(path, app=False):
        p = pp.file_probs(path, pw, design_bandpass, config, backend, app)
        return float(p.mean())

    rows = []
    for c in clips:
        f = c["new"]
        r = {"file": f, "source": c["source"], "label": int(c["label_true"]), "original": c["original"],
             "p_original": prob(orig_dir / f), "p_played": prob(played_dir / f)}
        img_ref = model_image(played_dir / f, pw, design_bandpass, config)
        for v, (sub, app) in variants.items():
            ps, rs, maes = [], [], []
            for run in a.runs:
                path = (HERE / "sim" / sub / f) if v in SHARED else (run / "pcg_clips" / sub / f)
                ps.append(prob(path, app))
                img = model_image(path, pw, design_bandpass, config, app)
                rs.append(float(np.corrcoef(img_ref.ravel(), img.ravel())[0, 1]))
                maes.append(float(np.mean(np.abs(img_ref - img))))
            ps = np.array(ps)
            r[f"p_{v}_mean"], r[f"p_{v}_std"] = ps.mean(), ps.std(ddof=1) if ps.size > 1 else 0.0
            r[f"p_{v}_runs"] = ";".join(f"{p:.4f}" for p in ps)
            r[f"sameclass_{v}_runs"] = int(np.sum((ps >= t) == (r["p_played"] >= t)))
            r[f"melr_{v}"], r[f"melmae_{v}"] = float(np.mean(rs)), float(np.mean(maes))
        rows.append(r)
        print(f'{f:24s} {c["source"]:9s} y={r["label"]}  played={r["p_played"]:.3f}  '
              f'steth={r["p_steth_mean"]:.3f}±{r["p_steth_std"]:.3f}  app={r["p_steth_app_mean"]:.3f}  '
              f'eq={r["p_steth_eq_mean"]:.3f}  melr={r["melr_steth"]:.3f}/{r["melr_steth_eq"]:.3f}')

    # per-run probability files
    for i, run in enumerate(a.runs):
        for v in variants:
            with open(run / f"{a.probs_prefix}_{v}.csv", "w", newline="", encoding="utf-8") as fh:
                w = csv.writer(fh)
                w.writerow(["file", "p_mean"])
                for r in rows:
                    w.writerow([r["file"], r[f"p_{v}_runs"].split(";")[i]])

    a.out.mkdir(parents=True, exist_ok=True)
    with open(a.out / "pcg_per_clip.csv", "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=list(rows[0]))
        w.writeheader()
        w.writerows(rows)

    # summary per group and variant
    groups = {"all": rows}
    for s in ("physionet", "pascal"):
        for l, ln in ((0, "normal"), (1, "abnormal")):
            groups[f"{s} {ln}"] = [r for r in rows if r["source"] == s and r["label"] == l]
    nruns = len(a.runs)
    summ = []
    for g, rs in groups.items():
        if not rs:
            continue
        y = np.array([r["label"] for r in rs])
        pp_ = np.array([r["p_played"] for r in rs])
        line = {"group": g, "n": len(rs), "runs": nruns,
                "acc_original": int(np.sum((np.array([r["p_original"] for r in rs]) >= t) == y)),
                "acc_played": int(np.sum((pp_ >= t) == y))}
        for v in variants:
            pm = np.array([r[f"p_{v}_mean"] for r in rs])
            same = sum(r[f"sameclass_{v}_runs"] for r in rs)
            runs_p = np.array([[float(p) for p in r[f"p_{v}_runs"].split(";")] for r in rs])
            line[f"acc_{v}_runmean"] = float(np.mean([np.sum((runs_p[:, i] >= t) == y) for i in range(nruns)]))
            line[f"agree_{v}_pct"] = 100.0 * same / (len(rs) * nruns)
            line[f"absdp_{v}_median"] = float(np.median(np.abs(pm - pp_)))
            line[f"p_{v}_runstd_median"] = float(np.median([r[f"p_{v}_std"] for r in rs]))
            line[f"melr_{v}_median"] = float(np.median([r[f"melr_{v}"] for r in rs]))
        summ.append(line)
    with open(a.out / "pcg_summary.csv", "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=list(summ[0]))
        w.writeheader()
        w.writerows(summ)

    print("\nSummary (agreement = same class as the played clip, over all clip x run pairs)")
    for s in summ:
        print(f'{s["group"]:20s} n={s["n"]:2d} acc orig={s["acc_original"]:2d} played={s["acc_played"]:2d} | '
              + " | ".join(f'{v}: agree {s[f"agree_{v}_pct"]:5.1f}% acc {s[f"acc_{v}_runmean"]:4.1f} '
                           f'|dp| {s[f"absdp_{v}_median"]:.3f} melr {s[f"melr_{v}_median"]:.3f}'
                           for v in variants))
    print(f"-> {a.out}")


if __name__ == "__main__":
    main()
