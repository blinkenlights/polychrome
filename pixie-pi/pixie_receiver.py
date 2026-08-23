#!/usr/bin/env python3
"""Empfaengt Octopus-Frames per UDP und gibt sie auf WS2812-Panels aus.

Gegenstueck zu blinkenleds/src/Display.cpp fuer den Raspberry Pi. Die
Paketbehandlung folgt handle_packet(); WFrame wird ignoriert, weil die
CJMCU-Panels keinen Weisskanal haben. Easing und Farbkalibrierung aus
Pixel.cpp fehlen bewusst.

Start:

    sudo ~/pixie-venv/bin/python ~/pixie-pi/pixie_receiver.py --verbose
"""

import argparse
import logging
import os
import socket
import sys
import time
from dataclasses import dataclass, field

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import schema_pb2  # noqa: E402  (liegt neben dieser Datei, per protoc erzeugt)

log = logging.getLogger("pixie")

# ---------------------------------------------------------------------------
# Konfiguration
# ---------------------------------------------------------------------------

UDP_PORT = 1337          # Controller.udp_port_base fuer Port 1 der :pixie-Kette
PANEL_W = 8
PANEL_H = 8
PIXELS_PER_PANEL = PANEL_W * PANEL_H

# Sicherheitsobergrenze fuer die Hardware. 64 LEDs auf Vollweiss ziehen bei
# 255 rund 3,8 A - weit mehr, als der 5V-Pin des Pi vertraegt. Erst mit
# externem Netzteil hochdrehen.
MAX_BRIGHTNESS = 30


@dataclass
class ChainConfig:
    """Eine GPIO-Kette. GPIO 18 haengt an PWM-Kanal 0, GPIO 13 an Kanal 1."""

    gpio: int
    channel: int
    dma: int
    panel_count: int


@dataclass
class PanelConfig:
    """Ein Panel in der Installation.

    frame_index  1-basierte Position im Frame, entspricht PANEL_INDEX in der
                 ESP32-Firmware und firmware_panel_index in controllers.ex.
                 Bestimmt, welchen 64-Pixel-Ausschnitt des Frames das Panel
                 aus dem Paket schneidet.
    chain        Index in CHAINS.
    position     Position innerhalb der Kette, 0-basiert. Ergibt den
                 LED-Offset: position * PIXELS_PER_PANEL.
    """

    frame_index: int
    chain: int
    position: int
    led_map: list[int] = field(default_factory=list, repr=False)


# Aktueller Aufbau: ein Panel an GPIO 18.
CHAINS = [
    ChainConfig(gpio=18, channel=0, dma=10, panel_count=1),
]
PANELS = [
    PanelConfig(frame_index=1, chain=0, position=0),
]

# Ausbaustufe mit 12 Panels an zwei Ketten - nur diese beiden Listen tauschen:
#
# CHAINS = [
#     ChainConfig(gpio=18, channel=0, dma=10, panel_count=6),
#     ChainConfig(gpio=13, channel=1, dma=11, panel_count=6),
# ]
# PANELS = [
#     PanelConfig(frame_index=i, chain=0 if i <= 6 else 1, position=(i - 1) % 6)
#     for i in range(1, 13)
# ]
#
# Zwei Ketten brauchen unterschiedliche DMA-Kanaele, sonst greifen sich die
# beiden PixelStrip-Instanzen gegenseitig an. 10 und 11 sind frei.


# ---------------------------------------------------------------------------
# Verdrahtung
#
# Die Daten kommen nicht in Bildschirmreihenfolge an. Octopus wendet in
# untangle.ex vor dem Senden WireMap.encode_to_firmware/4 an, das zwei
# Permutationen hintereinanderlegt:
#
#   1. Panel-Wiring - es nimmt an, das Panel sei :serpentine_vertical_bottom_left
#      verdrahtet (so sind die Polychrome-Panels montiert)
#   2. Firmware-Map - es rechnet vor, dass der Empfaenger map_index() aus
#      Display.cpp anwendet
#
# Beide Annahmen treffen auf die CJMCU-Boards nicht zu: die sind progressiv
# zeilenweise ab oben links verdrahtet, Layout-Index und LED-Position sind
# also identisch. Wir drehen deshalb beide Permutationen zurueck.
# ---------------------------------------------------------------------------


def strip_index(i: int, w: int = PANEL_W, h: int = PANEL_H) -> int:
    """Port von Display.cpp map_index() bzw. WireMap.strip_index/3.

    Serpentin horizontal ab unten links - was die ESP32-Firmware tut.
    """
    x = i % w
    y = h - 1 - i // w
    return y * w + (x if y % 2 == 0 else w - 1 - x)


def vertical_strip_to_layout(s: int, w: int = PANEL_W, h: int = PANEL_H) -> int:
    """Port von WireMap.vertical_strip_to_layout/3.

    Serpentin vertikal ab unten links - das Wiring, das Octopus annimmt.
    Liefert den Layout-Index (zeilenweise ab oben links).
    """
    x = s // h
    offset = s % h
    y_top = (h - 1 - offset) if x % 2 == 0 else offset
    return x + y_top * w


def build_led_map(w: int = PANEL_W, h: int = PANEL_H) -> list[int]:
    """Buffer-Index im Paket -> LED-Position auf dem CJMCU-Panel.

    Auf dem progressiv verdrahteten Panel ist die LED-Position gleich dem
    Layout-Index, deshalb faellt der letzte Schritt weg.
    """
    led_map = [vertical_strip_to_layout(strip_index(i, w, h), w, h) for i in range(w * h)]
    assert sorted(led_map) == list(range(w * h)), "Mapping ist keine Permutation"
    return led_map


# ---------------------------------------------------------------------------
# Ausgabe
# ---------------------------------------------------------------------------


class Chain:
    """Eine GPIO-Kette aus n hintereinandergeschalteten Panels."""

    def __init__(self, config: ChainConfig, brightness: int):
        from rpi_ws281x import PixelStrip, ws

        self.config = config
        self.led_count = config.panel_count * PIXELS_PER_PANEL
        self.strip = PixelStrip(
            self.led_count,
            config.gpio,
            800000,        # WS2812-Bitrate
            config.dma,
            False,         # nicht invertiert
            brightness,
            config.channel,
            ws.WS2811_STRIP_GRB,
        )
        self.strip.begin()
        self.dirty = False
        self.clear()
        self.show()

    def clear(self):
        for i in range(self.led_count):
            self.strip.setPixelColor(i, 0)
        self.dirty = True

    def set_pixel(self, index: int, r: int, g: int, b: int):
        self.strip.setPixelColor(index, (r << 16) | (g << 8) | b)
        self.dirty = True

    def show(self):
        if self.dirty:
            self.strip.show()
            self.dirty = False


# ---------------------------------------------------------------------------
# Paketverarbeitung - folgt Display.cpp handle_packet()
# ---------------------------------------------------------------------------


class Receiver:
    def __init__(self, chains: list[Chain], panels: list[PanelConfig]):
        self.chains = chains
        self.panels = panels
        self.luminance = 255
        self.stats = {"packets": 0, "frames": 0, "ignored": 0, "errors": 0}

    def handle(self, payload: bytes):
        self.stats["packets"] += 1
        packet = schema_pb2.Packet()
        try:
            packet.ParseFromString(payload)
        except Exception as exc:
            self.stats["errors"] += 1
            log.warning("Paket nicht dekodierbar (%d Bytes): %s", len(payload), exc)
            return

        which = packet.WhichOneof("content")

        if which == "firmware_config":
            # Nur die Luminanz interessiert uns. Easing-Modus und Kalibrierung
            # kommen spaeter, show_test_frame rendert die Firmware selbst.
            self.luminance = packet.firmware_config.luminance
            log.info("FirmwareConfig: luminance=%d", self.luminance)

        elif which == "rgb_frame":
            self._apply_rgb(packet.rgb_frame.data, part=None)
            self.stats["frames"] += 1

        elif which == "rgb_frame_part1":
            # split_and_encode/1 trennt bei 960 Bytes: Teil 1 traegt die
            # Panels 1 bis 5. Ein Einzelpanel-Frame landet ebenfalls hier.
            self._apply_rgb(packet.rgb_frame_part1.data, part=1)
            self.stats["frames"] += 1

        elif which == "rgb_frame_part2":
            self._apply_rgb(packet.rgb_frame_part2.data, part=2)
            self.stats["frames"] += 1

        else:
            # w_frame, audio_frame, input_event, ... gehen uns nichts an.
            self.stats["ignored"] += 1
            log.debug("Ignoriert: %s", which)
            return

        for chain in self.chains:
            chain.show()

    def _apply_rgb(self, data: bytes, part: int | None):
        scale = self.luminance / 255.0

        for panel in self.panels:
            # Welchen Ausschnitt des Frames schneidet dieses Panel heraus?
            # Entspricht der first_pixel-Rechnung in handle_packet().
            if part == 1:
                if panel.frame_index > 5:
                    continue
                first_pixel = PIXELS_PER_PANEL * (panel.frame_index - 1)
            elif part == 2:
                if panel.frame_index <= 5:
                    continue
                first_pixel = PIXELS_PER_PANEL * (panel.frame_index - 6)
            else:
                first_pixel = PIXELS_PER_PANEL * (panel.frame_index - 1)

            start = first_pixel * 3
            if len(data) < start + PIXELS_PER_PANEL * 3:
                log.warning(
                    "Frame zu kurz fuer Panel %d: %d Bytes, brauche %d",
                    panel.frame_index, len(data), start + PIXELS_PER_PANEL * 3,
                )
                continue

            chain = self.chains[panel.chain]
            led_offset = panel.position * PIXELS_PER_PANEL

            for k in range(PIXELS_PER_PANEL):
                o = start + k * 3
                chain.set_pixel(
                    led_offset + panel.led_map[k],
                    int(data[o] * scale),
                    int(data[o + 1] * scale),
                    int(data[o + 2] * scale),
                )


# ---------------------------------------------------------------------------
# Server
# ---------------------------------------------------------------------------


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=UDP_PORT)
    parser.add_argument("--brightness", type=int, default=MAX_BRIGHTNESS,
                        help=f"Hardware-Helligkeit 0-255 (Default {MAX_BRIGHTNESS})")
    parser.add_argument("--verbose", action="store_true", help="jedes Paket loggen")
    parser.add_argument("--stats-interval", type=float, default=5.0,
                        help="Sekunden zwischen Statistikzeilen, 0 schaltet sie ab")
    args = parser.parse_args()

    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(asctime)s %(levelname)-7s %(message)s",
        stream=sys.stdout,
    )

    if args.brightness > MAX_BRIGHTNESS:
        log.warning(
            "Helligkeit %d ueber der Sicherheitsgrenze %d. Nur mit externem "
            "Netzteil - ueber den 5V-Pin des Pi zieht ein volles Panel zu viel.",
            args.brightness, MAX_BRIGHTNESS,
        )

    led_map = build_led_map()
    for panel in PANELS:
        panel.led_map = led_map

    chains = [Chain(c, args.brightness) for c in CHAINS]
    log.info(
        "%d Kette(n), %d Panel(s), %d LEDs gesamt, Helligkeit %d",
        len(chains), len(PANELS), sum(c.led_count for c in chains), args.brightness,
    )

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind(("", args.port))
    log.info("Lausche auf UDP %d", args.port)

    receiver = Receiver(chains, PANELS)
    last_stats = time.monotonic()
    last_counts = dict(receiver.stats)
    senders = set()

    try:
        while True:
            sock.settimeout(1.0)
            try:
                payload, addr = sock.recvfrom(65535)
            except socket.timeout:
                payload = None
            else:
                if addr[0] not in senders:
                    senders.add(addr[0])
                    log.info("Erster Absender: %s:%d", addr[0], addr[1])
                receiver.handle(payload)

            now = time.monotonic()
            if args.stats_interval and now - last_stats >= args.stats_interval:
                dt = now - last_stats
                d = {k: receiver.stats[k] - last_counts[k] for k in receiver.stats}
                log.info(
                    "%.1f Pakete/s, %.1f Frames/s, ignoriert %d, Fehler %d",
                    d["packets"] / dt, d["frames"] / dt, d["ignored"], d["errors"],
                )
                last_stats = now
                last_counts = dict(receiver.stats)
    except KeyboardInterrupt:
        pass
    finally:
        for chain in chains:
            chain.clear()
            chain.show()
        log.info("Aus.")


if __name__ == "__main__":
    main()
