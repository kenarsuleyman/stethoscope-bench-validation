"""Run the deployed heart-sound classifier on WAV files with the training pipeline.

Imports the preprocessing and TFLite code of the training project (mems_python,
src/inference/predict_wav.py), so every file goes through exactly the training steps:
resample -> 4000 Hz, 5 s segments, Butterworth 25-900 Hz (zero-phase), peak-normalise,
log-mel -> 224x224x3, TFLite model; the file probability is the mean over segments.

Usage (from the matlab_test folder, with the venv python):
  python pcg_test/predict_pcg.py --golden-check
  python pcg_test/predict_pcg.py --wav-dir DIR --out probs.csv [--app-path]

--app-path  resample to 16 kHz first (Android AudioRecord rate in the app), then to 4 kHz,
            as the mobile app does; default is a direct resample to 4 kHz (training code).
"""

import argparse
import csv
import json
import sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
DEFAULT_MEMS = HERE.parent.parent / "mems_python"
DEFAULT_MODEL = HERE / "model" / "heart_sound_classifier_fp16.tflite"
APP_CAPTURE_SR = 16000


def load_pipeline(mems_root: Path):
    sys.path.insert(0, str(mems_root))
    from src.inference import predict_wav as pw
    from src.preprocessing.clean_filter import design_bandpass, load_config
    config = load_config(mems_root / "configs" / "config.yaml")
    return pw, design_bandpass, config


def load_tflite(model_path: Path, pw):
    """predict_wav.TFLiteModel, but loaded from bytes: the LiteRT C++ loader cannot open
    paths with non-ASCII characters (the project lives under 'Masaüstü')."""
    Interpreter = pw._import_tflite_interpreter()
    m = pw.TFLiteModel.__new__(pw.TFLiteModel)
    m.interp = Interpreter(model_content=model_path.read_bytes())
    m.interp.allocate_tensors()
    m.inp = m.interp.get_input_details()[0]
    m.out = m.interp.get_output_details()[0]
    return m


def file_probs(path: Path, pw, design_bandpass, config, backend, app_path: bool) -> np.ndarray:
    prep, mel_cfg = config["preprocessing"], config["mel_spectrogram"]
    target_sr = prep["target_sr"]
    audio, sr = pw.load_audio_mono(path)
    if app_path and sr != APP_CAPTURE_SR:
        audio, sr = pw.resample_to_target(audio, sr, APP_CAPTURE_SR), APP_CAPTURE_SR
    audio = pw.resample_to_target(audio, sr, target_sr)
    segs = pw.segment_audio(audio, target_sr * prep["segment_length_s"])
    sos = design_bandpass(prep["bandpass_low"], prep["bandpass_high"], target_sr,
                          prep["butterworth_order"])
    mels = [pw.preprocess_segment(s, sos, mel_cfg, target_sr, tuple(mel_cfg["image_size"]))
            for s in segs]
    return backend.predict_batch(mels) if mels else np.array([])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mems-root", type=Path, default=DEFAULT_MEMS)
    ap.add_argument("--model", type=Path, default=DEFAULT_MODEL)
    ap.add_argument("--wav-dir", type=Path)
    ap.add_argument("--recursive", action="store_true")
    ap.add_argument("--out", type=Path)
    ap.add_argument("--app-path", action="store_true")
    ap.add_argument("--golden-check", action="store_true")
    a = ap.parse_args()

    pw, design_bandpass, config = load_pipeline(a.mems_root)
    backend = load_tflite(a.model, pw)

    if a.golden_check:
        gdir = a.mems_root / "test_parity"
        golden = json.load(open(gdir / "golden.json", encoding="utf-8"))
        worst = 0.0
        for it in golden["items"]:
            p = file_probs(gdir / "wavs" / it["rn_filename"], pw, design_bandpass, config,
                           backend, a.app_path)
            ref = np.array(it["python_per_segment"])
            d = float(np.max(np.abs(p - ref))) if p.size == ref.size else float("inf")
            worst = max(worst, d)
            print(f'{it["rn_filename"][:56]:56s} golden={ref.mean():.4f} now={p.mean():.4f} '
                  f'max|diff|={d:.5f}')
        print(f"\nworst per-segment difference vs golden.json: {worst:.5f}")
        return

    pat = "**/*.wav" if a.recursive else "*.wav"
    rows = []
    for f in sorted(a.wav_dir.glob(pat)):
        p = file_probs(f, pw, design_bandpass, config, backend, a.app_path)
        rows.append({"file": f.relative_to(a.wav_dir).as_posix(), "n_seg": p.size,
                     "p_seg": ";".join(f"{v:.6f}" for v in p),
                     "p_mean": f"{p.mean():.6f}" if p.size else ""})
        print(f'{rows[-1]["file"]:50s} n={p.size} p={rows[-1]["p_mean"]}')
    if a.out:
        with open(a.out, "w", newline="", encoding="utf-8") as fh:
            w = csv.DictWriter(fh, fieldnames=list(rows[0]))
            w.writeheader()
            w.writerows(rows)
        print(f"-> {a.out}")


if __name__ == "__main__":
    main()
