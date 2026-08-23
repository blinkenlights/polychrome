#!/usr/bin/env python3
"""Schritt 2: Physikalische Verdrahtung des Panels ermitteln.

Der LED-Streifen ist elektrisch eine Kette (LED 0..63). Wie diese Kette auf
dem 8x8-Raster liegt, verraet nur ein Blick aufs Panel. Drei Modi:

  walk     Ein Pixel nach dem anderen, 0..63. Die Farbe wechselt alle
           8 Schritte, so sieht man die Zeilen-/Spaltengrenzen mitlaufen.
           Vor jedem Durchlauf blitzt das Panel kurz auf (Startsignal).

  bands    Alle 64 Pixel gleichzeitig, in 8 Farbbaendern zu je 8 LEDs.
           Ein Foto zeigt sofort, ob die Kette in Zeilen oder Spalten
           laeuft und in welcher Reihenfolge die Baender liegen.

  markers  Nur vier Pixel, mit eindeutigen Farben:
             LED 0  rot     Startecke der Kette
             LED 7  gruen   Ende des ersten Achterblocks -> Laufrichtung
             LED 8  blau    Start des zweiten -> serpentin oder progressiv
             LED 63 weiss   Ende der Kette
           Aus diesen vier Positionen laesst sich die Verdrahtung
           vollstaendig ableiten. Ein Foto genuegt.

Start (als root, mit dem venv-Interpreter):

    sudo ~/pixie-venv/bin/python ~/pixie-pi/02_mapping.py
    sudo ~/pixie-venv/bin/python ~/pixie-pi/02_mapping.py --mode bands
    sudo ~/pixie-venv/bin/python ~/pixie-pi/02_mapping.py --mode markers
"""

import argparse
import time

from rpi_ws281x import Color, PixelStrip, ws

LED_COUNT = 64
LED_PIN = 18
LED_FREQ_HZ = 800000
LED_DMA = 10
LED_BRIGHTNESS = 30
LED_INVERT = False
LED_CHANNEL = 0
LED_STRIP = ws.WS2811_STRIP_GRB

# Acht gut unterscheidbare Farben, eine pro Achterblock.
BAND_COLORS = [
    ("rot", Color(255, 0, 0)),
    ("gruen", Color(0, 255, 0)),
    ("blau", Color(0, 0, 255)),
    ("gelb", Color(255, 255, 0)),
    ("magenta", Color(255, 0, 255)),
    ("cyan", Color(0, 255, 255)),
    ("weiss", Color(255, 255, 255)),
    ("orange", Color(255, 90, 0)),
]

MARKERS = [
    (0, "rot", Color(255, 0, 0)),
    (7, "gruen", Color(0, 255, 0)),
    (8, "blau", Color(0, 0, 255)),
    (63, "weiss", Color(255, 255, 255)),
]


def clear(strip):
    for i in range(strip.numPixels()):
        strip.setPixelColor(i, Color(0, 0, 0))
    strip.show()


def run_walk(strip, delay):
    print(f"Modus: walk, {delay}s pro Pixel, Farbwechsel alle 8 Schritte.")
    print("Vor jedem Durchlauf blitzt das Panel kurz auf.", flush=True)
    while True:
        # Startsignal: kurzes gedimmtes Aufblitzen des ganzen Panels.
        for i in range(LED_COUNT):
            strip.setPixelColor(i, Color(40, 40, 40))
        strip.show()
        time.sleep(0.3)
        clear(strip)
        time.sleep(0.5)

        print("--- Durchlauf beginnt ---", flush=True)
        for i in range(LED_COUNT):
            name, color = BAND_COLORS[i // 8]
            clear(strip)
            strip.setPixelColor(i, color)
            strip.show()
            print(f"  LED {i:2d}  Block {i // 8}  {name}", flush=True)
            time.sleep(delay)
        clear(strip)
        time.sleep(1.0)


def run_bands(strip):
    print("Modus: bands. Alle 64 Pixel an, 8 Farbbaender zu je 8 LEDs:", flush=True)
    for block, (name, color) in enumerate(BAND_COLORS):
        lo, hi = block * 8, block * 8 + 7
        print(f"  LED {lo:2d}-{hi:2d}  {name}", flush=True)
        for i in range(lo, hi + 1):
            strip.setPixelColor(i, color)
    strip.show()
    print("Steht. Mach ein Foto. Ctrl-C zum Beenden.", flush=True)
    while True:
        time.sleep(1)


def run_markers(strip):
    print("Modus: markers. Vier Pixel:", flush=True)
    clear(strip)
    for index, name, color in MARKERS:
        print(f"  LED {index:2d}  {name}", flush=True)
        strip.setPixelColor(index, color)
    strip.show()
    print("Steht. Mach ein Foto. Ctrl-C zum Beenden.", flush=True)
    while True:
        time.sleep(1)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mode", choices=["walk", "bands", "markers"], default="walk")
    parser.add_argument("--delay", type=float, default=0.6, help="Sekunden pro Pixel im walk-Modus")
    args = parser.parse_args()

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

    try:
        if args.mode == "walk":
            run_walk(strip, args.delay)
        elif args.mode == "bands":
            run_bands(strip)
        else:
            run_markers(strip)
    except KeyboardInterrupt:
        pass
    finally:
        clear(strip)
        print("\nAus.", flush=True)


if __name__ == "__main__":
    main()
