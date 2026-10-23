// Teensy 4.0 + INMP441 USB microphone (firmware of the MEMS digital stethoscope).
// Recovered on 2026-10-23 from the Arduino IDE build folder of the old PC
// (sketch_jan24a, compiled 2026-01-24 15:42; original sketch was an unsaved IDE sketch).
// Board: Teensy 4.0, USB Type "Audio", 600 MHz, "Faster" (o2std), Teensyduino 1.59.
// The left I2S channel (INMP441 L/R pin to GND) is sent on both USB channels:
// the host sees a 2 ch / 44.1 kHz / 16 bit UAC1 device carrying the same signal twice.
#include <Audio.h>
#include <Wire.h>
#include <SPI.h>

// Audio bağlantıları
AudioInputI2S            i2sInput;
AudioOutputUSB           usbOutput;
AudioConnection          patchCord1(i2sInput, 0, usbOutput, 0);
AudioConnection          patchCord2(i2sInput, 0, usbOutput, 1);

void setup() {
  AudioMemory(60);
}

void loop() {
  // Boş - Audio library otomatik çalışır
}
