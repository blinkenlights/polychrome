#!/usr/bin/env python3
"""Schickt Testframes an den Empfaenger - ohne Octopus.

Baut die Pakete genau so, wie Octopus sie kodiert: Layout-Pixel werden per
WireMap.encode_to_firmware/4 in Firmware-Bufferreihenfolge gebracht und als
rgb_frame_part1 verpackt (das macht Protobuf.split_and_encode/1 bei einem
Einzelpanel-Frame).

Damit laesst sich pruefen, ob der Empfaenger die Permutation korrekt
zurueckdreht: was hier als Layout-Koordinate reingeht, muss auf dem Panel
an genau dieser Stelle leuchten.

    ~/pixie-venv/bin/python ~/pixie-pi/test_send_frame.py --pattern corner
    ~/pixie-venv/bin/python ~/pixie-pi/test_send_frame.py --pixel 0 0
"""

import argparse
import os
import socket
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import schema_pb2  # noqa: E402

W = H = 8
PIXELS = W * H


def strip_index(i: int, w: int = W, h: int = H) -> int:
    """Display.cpp map_index() - was die Firmware mit dem Buffer macht."""
    x = i % w
    y = h - 1 - i // w
    return y * w + (x if y % 2 == 0 else w - 1 - x)


def vertical_layout_to_strip(u: int, w: int = W, h: int = H) -> int:
    """WireMap.vertical_layout_to_strip/3 - das von Octopus angenommene Wiring."""
    x = u % w
    y_top = u // w
    return x * h + ((h - 1 - y_top) if x % 2 == 0 else y_top)


def build_buffer_order() -> list[int]:
    """Layout-Index -> Buffer-Index, also die Kodierung von Octopus."""
    # buffer[i] speist Strip-Position strip_index(i); wir brauchen die Umkehrung.
    buffer_of_strip = {strip_index(i): i for i in range(PIXELS)}
    return [buffer_of_strip[vertical_layout_to_strip(u)] for u in range(PIXELS)]


def encode(layout_pixels: dict[int, tuple[int, int, int]]) -> bytes:
    """Layout-Pixel {u: (r,g,b)} -> Frame in Firmware-Bufferreihenfolge."""
    buffer_of_layout = build_buffer_order()
    data = bytearray(PIXELS * 3)
    for u, (r, g, b) in layout_pixels.items():
        i = buffer_of_layout[u]
        data[i * 3 : i * 3 + 3] = bytes((r, g, b))
    return bytes(data)


def pattern_corner() -> dict[int, tuple[int, int, int]]:
    """Ecke weiss, obere Zeile rot, linke Spalte blau.

    Zeigt Orientierung und Spiegelung auf einen Blick: liegt Rot senkrecht
    oder Blau waagerecht, ist das Bild gedreht.
    """
    px = {}
    for x in range(1, W):
        px[x] = (255, 0, 0)              # obere Zeile
    for y in range(1, H):
        px[y * W] = (0, 0, 255)          # linke Spalte
    px[0] = (255, 255, 255)              # Ecke oben links
    return px


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=1337)
    parser.add_argument("--pattern", choices=["corner"], help="fertiges Testbild")
    parser.add_argument("--pixel", nargs=2, type=int, metavar=("X", "Y"),
                        help="einzelnes Layout-Pixel weiss setzen, 0 0 = oben links")
    args = parser.parse_args()

    if args.pixel:
        x, y = args.pixel
        if not (0 <= x < W and 0 <= y < H):
            sys.exit(f"Koordinate ausserhalb 0..{W - 1}")
        layout = {x + y * W: (255, 255, 255)}
        print(f"Setze Layout-Pixel ({x}, {y}) auf weiss")
    else:
        layout = pattern_corner()
        print("Testbild 'corner': Ecke oben links weiss, obere Zeile rot, "
              "linke Spalte blau")

    frame = schema_pb2.RGBFrame(data=encode(layout), easing_interval=0)
    packet = schema_pb2.Packet(rgb_frame_part1=frame)
    payload = packet.SerializeToString()

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.sendto(payload, (args.host, args.port))
    print(f"{len(payload)} Bytes an {args.host}:{args.port} gesendet "
          f"(rgb_frame_part1, {len(frame.data)} Bytes Pixeldaten)")


if __name__ == "__main__":
    main()
