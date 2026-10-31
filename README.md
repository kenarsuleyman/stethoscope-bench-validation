# Bench acoustic validation of a MEMS digital stethoscope

Measurement and analysis code for the paper

> S. Kenar, U. Aydemir. *Bench acoustic evaluation of a low-cost MEMS-based digital stethoscope for a heart sound
> classifier trained on public datasets* (submitted to Physiological Measurement).

The stethoscope is a commercial dual-head chestpiece, a shortened tube, a 3D-printed PLA coupler, an INMP441 MEMS
microphone and a Teensy 4.0 that streams the microphone as a USB Audio Class 1.0 device (2 ch, 44.1 kHz, 16 bit).
A MobileNetV2 heart sound classifier, trained on public datasets, runs in an Android application. This repository
tests whether the hardware preserves what the classifier needs:

1. **Pure tones** (30 Hz to 6 kHz): frequency accuracy, level response, in-band SNR, THD, sample slips,
   repeatability with and without re-seating the chestpiece, THD versus playback level, tube length, and an
   exponential sine sweep for the exact resonance frequencies.
2. **Heart sound playback**: 47 segments of PhysioNet/CinC 2016 and PASCAL Dataset-B played through the same setup and
   re-recorded; transfer function, coherence, envelope and Mel-image correlation, and the model decisions on the played
   and recorded segments (decision consistency, forward simulation with the measured response, response correction).
3. **Smartphone recording path**: the same playback recorded by the Android application (AudioRecord, UNPROCESSED,
   16 kHz) and compared with the computer recording: decisions, level (tones recorded before, during and after),
   and the noise floor with the coupler inlet open and sealed.

## Related repositories and data

| What | Where |
|---|---|
| Training, evaluation and TFLite export of the classifier | [kenarsuleyman/digital-stethoscope](https://github.com/kenarsuleyman/digital-stethoscope) |
| Android application (React Native) | [kenarsuleyman/digital-stethoscope-mobile](https://github.com/kenarsuleyman/digital-stethoscope-mobile) |
| Raw recordings of all runs used in the paper, the 47 played segments, the TFLite model | Zenodo: [10.5281/zenodo.23613295](https://doi.org/10.5281/zenodo.23613295) |

## Requirements

- MATLAB R2026a or later with Audio Toolbox, DSP System Toolbox and Signal Processing Toolbox.
- Python 3.12 with the requirements of the training repository (TensorFlow / LiteRT, librosa, scipy, soundfile).
  The scripts in `pcg_test/` import its preprocessing: clone it next to this repository as `mems_python`
  (`../mems_python`), or edit `DEFAULT_MEMS` in `pcg_test/predict_pcg.py`.
- For new measurements: the stethoscope on USB, a speaker (here a wired headphone driver in a foam-lined box) and the
  device names set in `config.m` (`list_audio_devices` prints them).

## Layout

| Path | Content |
|---|---|
| `config.m` | every parameter: tone list, durations, levels, devices, analysis settings, figure style |
| `generate_test_signal.m`, `generate_pcg_stimulus.m` | stepped-tone and heart-sound stimuli with sync chirps and a silent section |
| `run_measurement.m` | plays a stimulus and records the stethoscope; raw WAV + `meta.mat` in `data/<timestamp>_<label>/` |
| `play_stimulus.m`, `import_phone_recording.m` | smartphone path: play only, then import the WAV + JSON written by the app's test mode |
| `analyze_measurement.m`, `make_figures.m` | pure-tone analysis and figures (single run or mean ± std of several runs) |
| `analyze_pcg.m`, `make_pcg_figures.m` | heart-sound playback analysis and figures |
| `tone_band_snr.m`, `analyze_slips.m`, `pcg_coherence_check.m`, `pcg_forward_sim.m` | in-band SNR, USB sample slips, coherence, forward simulation and partial correction |
| `compare_r9_r10.m`, `compare_tube_length.m` | THD versus level and re-seating repeatability; 450 mm versus 300 mm tube |
| `generate_sweep.m`, `analyze_sweep.m` | exponential sine sweep (Farina) stimulus and response by regularized deconvolution (`run_measurement(label,'pc','sweep')`) |
| `pcg_coherence_lowband.m` | coherence below 50 Hz: measured versus noise-only and ideal linear system |
| `compare_phone_level.m` | smartphone versus computer level from tone runs before, during and after; sweep peaks |
| `record_silence.m`, `noise_floor_compare.m` | silence recordings (e.g. coupler inlet sealed) and noise floor comparison of computer and smartphone |
| `stetoskop_gui.m` | optional graphical interface for all measurement and analysis scripts (tools in `private/gui_tools.m`; labels in Turkish) |
| `self_test.m`, `pcg_self_test.m` | synthetic tests of the analysis code |
| `private/` | shared helpers (chirp detection, tone metrics, response correction, figure style) |
| `pcg_test/*.py` | segment selection, model inference on played / recorded / simulated segments, statistics (Wilson CI, McNemar) |
| `pcg_test/clips/filename_map.csv` | the 47 segments: source file, segment, dataset, true label |
| `pcg_test/results/`, `results/` | result tables used in the paper |
| `firmware/teensy40_usb_mic/` | Teensy 4.0 firmware (Teensy Audio Library, Teensyduino 1.59) |

## Reproducing the analysis

Download the Zenodo archive and unpack it so that the run folders are in `data/`, the segments in `pcg_test/clips/`
and the model in `pcg_test/model/`. Then, for example:

```matlab
% pure tones, three untouched runs (paper Fig. 2-3)
make_figures({'data/20261009_140429_diyafram_run1','data/20261009_140717_diyafram_run2','data/20261009_140956_diyafram_run3'})
% re-seating and THD versus level
r = dir('data/*_reseat_run*'); t = dir('data/*_thd_m*dB');
compare_r9_r10(fullfile('data',{r.name}), fullfile('data',{t.name}))
% heart-sound playback
analyze_pcg('data/20261009_190101_pcg_run1')      % per run, writes pcg_clips/
```

```bash
python pcg_test/pcg_model_compare.py data/20261009_190101_pcg_run1 data/20261009_190630_pcg_run2 data/20261009_191158_pcg_run3
python pcg_test/pcg_stats.py
```

New measurements: `list_audio_devices`, then `run_measurement('label')` for tones or
`run_measurement('label','pc','pcg')` for heart sounds (do not touch the setup between runs). The same scripts can be
run from `stetoskop_gui`, which writes every run with its log and command to `cikti/<tool>/<timestamp>/`; called
from the command line, the scripts behave as before.

## Notes

- Figure labels are Turkish by default; set `cfg.lang = 'en'` in `config.m` (most figure functions write both).
- The heart sound segments come from PhysioNet/CinC 2016 (ODC-BY 1.0) and PASCAL Classifying Heart Sounds Challenge
  Dataset-B; they are not stored here. `pcg_test/select_clips.py` rebuilds the selection from the original datasets
  (fixed seed) using the training repository's split.

## License

Code: MIT (see `LICENSE`). Datasets: see their original licenses.

## Citation

See `CITATION.cff`.
