# Blinkenleds

ESP32 Firmware for the LED Panels. It listens for UDP broadcasts that contain the protobuf frames and selects the relevant pixels to display.

It has easing support that can be configured via a config frame.

# Dependencies

* PlatformIO (build and dev framework)
* NeoPixelBus (Rendering Pixels)
* Nanopb (Protobufs for embedded systems)

# Client Messages
The firmware regulary sends messages that contain stats and the hash of the current config.

# Hardware
It is build for the QuinLed ESP32 with the ethernet shield. But it should work on any other ESP32.

RGBW LEDs with the TM1814 chipset are used.

## Wire colors 
green/yellow: Data
blue: v-
brown: v+

# Power consumption

64 TM1814 Led modules
disabled calibration
Power Supply: 12V * 8.5A = 102W

* Test Frame (Rainbow): 49W
* White RGB(255,255,255): 70W
* Dimm white RGB(128, 128, 128): 43W
* Red RGB(255, 0, 0): 31W
* Red+Green RGB(255,255,0): 50W
* All on, RGBW(255,255,255,255): 84W
* WW only, RGBW(0,0,0,255): 33W
