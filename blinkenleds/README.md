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