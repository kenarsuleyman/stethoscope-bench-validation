# Teensy 4.0 firmware (recovered)

Source: old PC SSD (`D:\Users\kenar\AppData\Local\arduino\sketches\9196B6D45DB53FE534AF76644DA72AFA`).
The sketch was an unsaved Arduino IDE 2 sketch (`sketch_jan24a`), so only the build folder survived.
`teensy40_usb_mic.ino` is rebuilt from the preprocessed `sketch_jan24a.ino.cpp` (code identical).

| File | What |
|---|---|
| `teensy40_usb_mic.ino` | sketch (AudioInputI2S ch 0 -> AudioOutputUSB L and R, AudioMemory(60)) |
| `sketch_jan24a.ino.hex` | binary compiled on 2026-01-24 15:42 (can be flashed with Teensy Loader) |
| `build.options.json` | FQBN `teensy:avr:teensy40:usb=audio,speed=600,opt=o2std,keys=en-us` |
| `sketch_jan24a.ino.cpp.preprocessed` | Arduino preprocessor output (original evidence) |

Build: Arduino IDE 2 + Teensyduino 1.59.0, Teensy Audio Library from that release.

## Library behaviour that matters for the measurements (Teensyduino 1.59, `cores/teensy4/usb_audio.cpp`)
- I2S DMA reads the upper 16 bits of each 32-bit slot (`input_i2s.cpp`, `&I2S1_RDR0 + 2`): 16 MSBs of the
  24-bit INMP441 word, no gain.
- `AUDIO_SAMPLE_RATE_EXACT = 44100`, blocks of 128 samples.
- `usb_audio_transmit_callback()` sends a fixed pattern of nine 44-sample packets and one 45-sample packet
  (441 samples per 10 ms of USB frames); comment in the source: "TODO: dynamic adjust to match USB rate".
- `AudioOutputUSB::update()` keeps two blocks; on overrun ("PC is consuming too slowly") it discards the rest
  of the oldest block. With the I2S clock slightly faster than the host frame clock the overrun is hit as soon
  as the excess reaches about one sample, so single samples are dropped -> the +0.94 sample phase steps every
  2.83 s (~7.5 ppm) measured by `analyze_slips.m`. On underrun the rest of a packet is zero-filled.
