#!/usr/bin/env python3
"""Schritt 1: Minimaltest der WS2812-Ansteuerung.

Setzt Pixel 0 auf Rot und laesst es an, bis Ctrl-C kommt. Mehr nicht --
das reicht, um Verkabelung, PWM/DMA-Zugriff und Farbreihenfolge zu pruefen.

Start (als root, mit dem venv-Interpreter):

    sudo ~/pixie-venv/bin/python pixie-pi/01_single_pixel.py
"""

import time

from rpi_ws281x import Color, PixelStrip, ws

LED_COUNT = 64          # ein CJMCU 8x8 Panel
LED_PIN = 18            # GPIO 18 = PWM0
LED_FREQ_HZ = 800000    # WS2812 Bitrate
LED_DMA = 10            # DMA-Kanal; 10 ist der uebliche freie Kanal
LED_BRIGHTNESS = 30     # von 255 -- absichtlich niedrig, siehe README
LED_INVERT = False      # True nur bei invertierendem Levelshifter
LED_CHANNEL = 0         # GPIO 18 haengt an PWM-Kanal 0

# WS2812B erwartet die Bytes in der Reihenfolge G,R,B. Leuchtet Pixel 0
# gruen statt rot, hier auf ws.WS2811_STRIP_RGB umstellen.
LED_STRIP = ws.WS2811_STRIP_GRB


def main():
    strip = PixelStrip(
        LED_COUNT,
        LED_PIN,
        LED_FREQ_HZ,
        LED_DMA,
        LED_INVERT,
        LED_BRIGHTNESS,
        LED_CHANNEL,
        LED_STRIP,
    )
    strip.begin()

    # Definierter Startzustand: erst alles aus, dann genau ein Pixel an.
    for i in range(LED_COUNT):
        strip.setPixelColor(i, Color(0, 0, 0))
    strip.setPixelColor(0, Color(255, 0, 0))
    strip.show()

    print("Pixel 0 sollte rot leuchten. Ctrl-C zum Beenden.")
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        pass
    finally:
        for i in range(LED_COUNT):
            strip.setPixelColor(i, Color(0, 0, 0))
        strip.show()
        print("\nAus.")


if __name__ == "__main__":
    main()
