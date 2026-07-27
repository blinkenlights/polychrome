#!/usr/bin/env python3
"""Build TouchOSC Mk1 .touchosc (zip + index.xml) for Pixel Fun 3D v1.

Stdlib only. Run from repo root or this directory:

    python3 octopus/priv/touchosc/build_mk1_layout.py
"""

from __future__ import annotations

import zipfile
from pathlib import Path
from xml.sax.saxutils import escape

OUT = Path(__file__).with_name("pixelfun3d-v1.touchosc")

# iPad landscape-ish canvas (Mk1 mode=1 is iPad in many builds; custom via coordinates)
W, H = 1024, 768

FADERS = [
    ("speed", "Speed", "/global/speed", 0.01, 10.0, "red"),
    ("bright", "Bright", "/pixelfun3d/brightness_percent", 0.0, 100.0, "orange"),
    ("zoom", "Zoom", "/pixelfun3d/zoom_base", 0.7, 11.0, "yellow"),
    ("rot", "Rot", "/pixelfun3d/roll_rate", -180.0, 180.0, "green"),
    ("tx", "TX", "/pixelfun3d/orbit_rate", -30.0, 30.0, "green"),
    ("ty", "TY", "/pixelfun3d/elev_base", -4.0, 4.0, "green"),
    ("sway", "Sway", "/pixelfun3d/tilt_scale", 0.0, 4.0, "purple"),
    ("sat", "Sat", "/pixelfun3d/saturation_percent", 0.0, 100.0, "blue"),
    ("tempo", "Tempo", "/pixelfun3d/color_interval", 1.0, 120.0, "blue"),
    ("bleed", "Bleed", "/pixelfun3d/bleeding", 0.0, 100.0, "gray"),
]

SCENES = [
    ("classic_ripple", "Classic"),
    ("nordlicht", "Nordlicht"),
    ("doppelhelix", "Doppelhelix"),
    ("leuchtplankton", "Plankton"),
    ("sternenhimmel", "Sterne"),
    ("marmor", "Marmor"),
    ("strudel", "Strudel"),
    ("nebelringe", "Nebel"),
]


def control_attrs(**kwargs) -> str:
    parts = []
    for key, value in kwargs.items():
        parts.append(f'{key}="{escape(str(value))}"')
    return " ".join(parts)


def label(name: str, text: str, x: int, y: int, w: int, h: int) -> str:
    return (
        f'    <control name="{escape(name)}" type="labelh" '
        f'x="{x}" y="{y}" w="{w}" h="{h}" color="white" text="{escape(text)}"/>'
    )


def faderv(name: str, x: int, y: int, w: int, h: int, address: str, lo: float, hi: float, color: str) -> str:
    return (
        f'    <control name="{escape(name)}" type="faderv" '
        f'x="{x}" y="{y}" w="{w}" h="{h}" color="{color}" '
        f'scalef="{lo}" scalet="{hi}" '
        f'osc_cs="{escape(address)}" osc_typ="f"/>'
    )


def toggle(name: str, x: int, y: int, w: int, h: int, address: str, color: str) -> str:
    return (
        f'    <control name="{escape(name)}" type="toggle" '
        f'x="{x}" y="{y}" w="{w}" h="{h}" color="{color}" '
        f'scalef="0" scalet="1" '
        f'osc_cs="{escape(address)}" osc_typ="f"/>'
    )


def push(name: str, x: int, y: int, w: int, h: int, address: str, color: str) -> str:
    return (
        f'    <control name="{escape(name)}" type="push" '
        f'x="{x}" y="{y}" w="{w}" h="{h}" color="{color}" '
        f'scalef="0" scalet="1" '
        f'osc_cs="{escape(address)}" osc_typ="f"/>'
    )


def build_perf_page() -> str:
    lines = ['  <tabpage name="perf" text="Performance">']
    lines.append(label("title_perf", "Pixel Fun 3D", 20, 10, 400, 30))

    n = len(FADERS)
    margin = 20
    gap = 8
    usable = W - 2 * margin
    col_w = (usable - gap * (n - 1)) // n
    fader_h = 480
    fader_y = 70
    label_h = 28

    for i, (name, text, address, lo, hi, color) in enumerate(FADERS):
        x = margin + i * (col_w + gap)
        lines.append(label(f"l_{name}", text, x, fader_y - label_h, col_w, label_h))
        lines.append(faderv(name, x, fader_y, col_w, fader_h, address, lo, hi, color))

    row_y = fader_y + fader_h + 30
    btn_h = 70
    btn_w = 140
    x = margin
    lines.append(label("l_freeze", "Freeze", x, row_y - 24, btn_w, 24))
    lines.append(toggle("freeze", x, row_y, btn_w, btn_h, "/pixelfun3d/time_frozen", "orange"))
    x += btn_w + 16
    lines.append(label("l_dir", "Dir 0=fwd", x, row_y - 24, btn_w, 24))
    lines.append(toggle("direction", x, row_y, btn_w, btn_h, "/pixelfun3d/time_direction", "yellow"))
    x += btn_w + 16
    lines.append(push("panic", x, row_y, btn_w, btn_h, "/pixelfun3d/panic", "red"))
    lines.append(label("l_panic", "PANIC", x, row_y - 24, btn_w, 24))
    x += btn_w + 16
    lines.append(push("sync", x, row_y, btn_w, btn_h, "/pixelfun3d/config", "gray"))
    lines.append(label("l_sync", "Sync", x, row_y - 24, btn_w, 24))

    lines.append("  </tabpage>")
    return "\n".join(lines)


def build_scenes_page() -> str:
    lines = ['  <tabpage name="scenes" text="Scenes">']
    lines.append(label("title_scenes", "Scenes — press to fire", 20, 10, 500, 30))

    cols, rows = 4, 2
    margin = 40
    gap = 20
    top = 80
    usable_w = W - 2 * margin
    usable_h = H - top - margin
    bw = (usable_w - gap * (cols - 1)) // cols
    bh = (usable_h - gap * (rows - 1)) // rows

    for i, (slug, title) in enumerate(SCENES):
        c, r = i % cols, i // cols
        x = margin + c * (bw + gap)
        y = top + r * (bh + gap)
        addr = f"/pixelfun3d/scenes/{slug}/fire"
        lines.append(push(f"sc_{slug}", x, y, bw, bh, addr, "purple"))
        lines.append(label(f"sl_{slug}", title, x, y + bh // 2 - 15, bw, 30))

    lines.append("  </tabpage>")
    return "\n".join(lines)


def build_xml() -> str:
    return "\n".join(
        [
            '<?xml version="1.0" encoding="UTF-8"?>',
            "<xml>",
            f'  <layout version="17" mode="1" orientation="horizontal">',
            build_perf_page(),
            build_scenes_page(),
            "  </layout>",
            "</xml>",
            "",
        ]
    )


def main() -> None:
    xml = build_xml()
    with zipfile.ZipFile(OUT, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        zf.writestr("index.xml", xml)
    print(f"Wrote {OUT}")


if __name__ == "__main__":
    main()
