#!/usr/bin/env python3
"""Schritt 3: Stromaufnahme des Panels messen.

Faehrt definierte statische Lastzustaende an und wartet nach jedem auf
Enter, damit sich der Messwert am Multimeter beruhigen kann. Optional
laesst sich der abgelesene Wert eintippen; am Ende steht eine Tabelle.

Statisch ist wichtig: bei laufender Animation springt der Zeiger, und
gemessen wird dann irgendwas zwischen den Frames.

Das Multimeter haengt in Reihe in der 5V-Leitung zum Panel, nicht
parallel. Rote Leitung in die 10A-Buchse, schwarze in COM, Drehschalter
auf 10A, mit SELECT auf DC stellen.

Start (als root, mit dem venv-Interpreter):

    sudo ~/pixie-venv/bin/python ~/pixie-pi/03_power_test.py
    sudo ~/pixie-venv/bin/python ~/pixie-pi/03_power_test.py --levels 10,30
    sudo ~/pixie-venv/bin/python ~/pixie-pi/03_power_test.py --hold white --brightness 30
"""

import argparse
import sys
import time

from rpi_ws281x import Color, PixelStrip, ws

LED_COUNT = 64
LED_PIN = 18
LED_FREQ_HZ = 800000
LED_DMA = 10
LED_INVERT = False
LED_CHANNEL = 0
LED_STRIP = ws.WS2811_STRIP_GRB

# Ueber diesem Wert nur mit externem Netzteil, siehe README. 64 LEDs auf
# Vollweiss ziehen bei 255 rund 3,8 A - das zieht der 5V-Pin des Pi nicht.
SAFE_BRIGHTNESS = 30

# (Name, Anzahl LEDs, Farbe). Die Reihenfolge geht von klein nach gross,
# damit ein zu hoher Wert auffaellt, bevor das ganze Panel an ist.
PATTERNS = [
    ("aus", 0, Color(0, 0, 0)),
    ("1 px weiss", 1, Color(255, 255, 255)),
    ("8 px weiss", 8, Color(255, 255, 255)),
    ("alle rot", LED_COUNT, Color(255, 0, 0)),
    ("alle gruen", LED_COUNT, Color(0, 255, 0)),
    ("alle blau", LED_COUNT, Color(0, 0, 255)),
    ("alle weiss", LED_COUNT, Color(255, 255, 255)),
]

PATTERNS_BY_NAME = {
    "off": PATTERNS[0],
    "one": PATTERNS[1],
    "eight": PATTERNS[2],
    "red": PATTERNS[3],
    "green": PATTERNS[4],
    "blue": PATTERNS[5],
    "white": PATTERNS[6],
}


def apply(strip, count, color, brightness):
    strip.setBrightness(brightness)
    for i in range(LED_COUNT):
        strip.setPixelColor(i, color if i < count else Color(0, 0, 0))
    strip.show()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--levels", default="10,20,30",
                        help="Helligkeitsstufen, kommagetrennt (Default 10,20,30)")
    parser.add_argument("--hold", choices=sorted(PATTERNS_BY_NAME),
                        help="ein Muster halten statt der Messreihe")
    parser.add_argument("--brightness", type=int, default=SAFE_BRIGHTNESS,
                        help=f"Helligkeit fuer --hold (Default {SAFE_BRIGHTNESS})")
    parser.add_argument("--seconds", type=float,
                        help="Haltedauer fuer --hold in Sekunden statt auf Enter zu warten. "
                             "Ohne Terminal (z.B. ueber ssh) sind 60s der Default.")
    parser.add_argument("--unsafe", action="store_true",
                        help=f"Stufen ueber {SAFE_BRIGHTNESS} zulassen - nur mit externem Netzteil")
    args = parser.parse_args()

    try:
        levels = [int(x) for x in args.levels.split(",") if x.strip()]
    except ValueError:
        sys.exit("--levels erwartet Zahlen, z.B. 10,20,30")

    requested = levels + ([args.brightness] if args.hold else [])
    too_high = [b for b in requested if b > SAFE_BRIGHTNESS]
    if too_high and not args.unsafe:
        sys.exit(
            f"Helligkeit {max(too_high)} ueber der Sicherheitsgrenze {SAFE_BRIGHTNESS}. "
            "Nur mit externem Netzteil, dann --unsafe setzen."
        )
    if not all(0 <= b <= 255 for b in requested):
        sys.exit("Helligkeit muss zwischen 0 und 255 liegen")

    strip = PixelStrip(LED_COUNT, LED_PIN, LED_FREQ_HZ, LED_DMA, LED_INVERT,
                       SAFE_BRIGHTNESS, LED_CHANNEL, LED_STRIP)
    strip.begin()

    try:
        if args.hold:
            name, count, color = PATTERNS_BY_NAME[args.hold]
            apply(strip, count, color, args.brightness)
            if args.seconds is None and sys.stdin.isatty():
                print(f"{name}, Helligkeit {args.brightness}. Steht. Ctrl-C zum Beenden.")
                while True:
                    input()
            else:
                seconds = args.seconds if args.seconds is not None else 60.0
                print(f"{name}, Helligkeit {args.brightness}. Steht fuer {seconds:.0f}s.",
                      flush=True)
                time.sleep(seconds)
            return

        print("Multimeter in Reihe in der 5V-Leitung, 10A-Buchse, DC.")
        print("Nach jedem Schritt Enter. Messwert in mA eintippen ist optional.\n")

        results = []
        for brightness in levels:
            print(f"--- Helligkeit {brightness} ---")
            for name, count, color in PATTERNS:
                apply(strip, count, color, brightness)
                answer = input(f"  {name:<12} steht. Messwert mA > ").strip()
                results.append((brightness, name, answer or "-"))
            print()

        print("\nHelligkeit  Muster        mA")
        for brightness, name, value in results:
            print(f"{brightness:>10}  {name:<12}  {value}")
    except (KeyboardInterrupt, EOFError):
        pass
    finally:
        apply(strip, 0, Color(0, 0, 0), SAFE_BRIGHTNESS)
        print("\nAus.")


if __name__ == "__main__":
    main()
