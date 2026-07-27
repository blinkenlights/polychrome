#!/usr/bin/env python3
"""Build TouchOSC Mk2 layout (lexml XML + zlib .tosc) for Pixel Fun 3D v1.

Stdlib only. Run:

    python3 octopus/priv/touchosc/build_mk2_layout.py

Outputs next to this script:
  - pixelfun3d-v1.xml   (open/import in TouchOSC 1.5.x)
  - pixelfun3d-v1.tosc  (native Mk2 project)
"""

from __future__ import annotations

import uuid
import zlib
from pathlib import Path
from xml.etree.ElementTree import Element, SubElement, tostring

DIR = Path(__file__).resolve().parent
XML_OUT = DIR / "pixelfun3d-v1.xml"
TOSC_OUT = DIR / "pixelfun3d-v1.tosc"

W, H = 1280, 800

FADERS = [
    # name, label, address, min, max, rgba
    ("speed", "Speed", "/global/speed", 0.01, 10.0, (0.9, 0.2, 0.2, 1)),
    ("bright", "Bright", "/pixelfun3d/brightness_percent", 0.0, 100.0, (0.95, 0.55, 0.15, 1)),
    ("zoom", "Zoom", "/pixelfun3d/zoom_base", 0.7, 11.0, (0.95, 0.85, 0.2, 1)),
    ("rot", "Rot", "/pixelfun3d/roll_rate", -180.0, 180.0, (0.3, 0.75, 0.35, 1)),
    ("tx", "TX", "/pixelfun3d/orbit_rate", -30.0, 30.0, (0.3, 0.7, 0.45, 1)),
    ("ty", "TY", "/pixelfun3d/elev_base", -4.0, 4.0, (0.3, 0.65, 0.55, 1)),
    ("sway", "Sway", "/pixelfun3d/tilt_scale", 0.0, 4.0, (0.6, 0.35, 0.85, 1)),
    ("sat", "Sat", "/pixelfun3d/saturation_percent", 0.0, 100.0, (0.25, 0.45, 0.9, 1)),
    ("tempo", "Tempo", "/pixelfun3d/color_interval", 1.0, 120.0, (0.25, 0.55, 0.95, 1)),
    ("bleed", "Bleed", "/pixelfun3d/bleeding", 0.0, 100.0, (0.55, 0.55, 0.55, 1)),
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


def new_id() -> str:
    return str(uuid.uuid4())


def prop(parent: Element, ptype: str, key: str) -> Element:
    p = SubElement(parent, "property", type=ptype)
    k = SubElement(p, "key")
    k.text = key
    return SubElement(p, "value")


def prop_bool(parent: Element, key: str, value: bool) -> None:
    prop(parent, "b", key).text = "1" if value else "0"


def prop_int(parent: Element, key: str, value: int) -> None:
    prop(parent, "i", key).text = str(value)


def prop_float(parent: Element, key: str, value: float) -> None:
    prop(parent, "f", key).text = str(value)


def prop_str(parent: Element, key: str, value: str) -> None:
    prop(parent, "s", key).text = value


def prop_color(parent: Element, key: str, rgba: tuple[float, float, float, float]) -> None:
    v = prop(parent, "c", key)
    for tag, val in zip("rgba", rgba):
        SubElement(v, tag).text = str(val)


def prop_frame(parent: Element, x: float, y: float, w: float, h: float) -> None:
    v = prop(parent, "r", "frame")
    SubElement(v, "x").text = str(x)
    SubElement(v, "y").text = str(y)
    SubElement(v, "w").text = str(w)
    SubElement(v, "h").text = str(h)


def value_slot(
    parent: Element,
    key: str,
    default: str,
    *,
    locked_default_current: int = 0,
) -> None:
    values = parent.find("values")
    if values is None:
        values = SubElement(parent, "values")
    slot = SubElement(values, "value")
    k = SubElement(slot, "key")
    k.text = key
    SubElement(slot, "locked").text = "0"
    SubElement(slot, "lockedDefaultCurrent").text = str(locked_default_current)
    d = SubElement(slot, "default")
    d.text = default
    SubElement(slot, "defaultPull").text = "0"


def osc_message(
    parent: Element,
    address: str,
    *,
    scale_min: float,
    scale_max: float,
    trigger_var: str = "x",
    feedback: bool = True,
) -> None:
    messages = parent.find("messages")
    if messages is None:
        messages = SubElement(parent, "messages")

    osc = SubElement(messages, "osc")
    SubElement(osc, "enabled").text = "1"
    SubElement(osc, "send").text = "1"
    SubElement(osc, "receive").text = "1"
    SubElement(osc, "feedback").text = "1" if feedback else "0"
    SubElement(osc, "connections").text = "00001"

    triggers = SubElement(osc, "triggers")
    trigger = SubElement(triggers, "trigger")
    var = SubElement(trigger, "var")
    var.text = trigger_var
    SubElement(trigger, "condition").text = "ANY"

    path = SubElement(osc, "path")
    partial = SubElement(path, "partial")
    SubElement(partial, "type").text = "CONSTANT"
    SubElement(partial, "conversion").text = "STRING"
    val = SubElement(partial, "value")
    val.text = address
    SubElement(partial, "scaleMin").text = "0"
    SubElement(partial, "scaleMax").text = "1"

    args = SubElement(osc, "arguments")
    arg = SubElement(args, "partial")
    SubElement(arg, "type").text = "VALUE"
    SubElement(arg, "conversion").text = "FLOAT"
    aval = SubElement(arg, "value")
    aval.text = trigger_var
    SubElement(arg, "scaleMin").text = str(scale_min)
    SubElement(arg, "scaleMax").text = str(scale_max)


def common_node(
    ntype: str,
    name: str,
    frame: tuple[float, float, float, float],
    color: tuple[float, float, float, float],
    *,
    interactive: bool = True,
) -> Element:
    node = Element("node", ID=new_id(), type=ntype)
    props = SubElement(node, "properties")
    prop_bool(props, "background", True)
    prop_color(props, "color", color)
    prop_float(props, "cornerRadius", 4.0)
    prop_frame(props, *frame)
    prop_bool(props, "grabFocus", interactive)
    prop_bool(props, "interactive", interactive)
    prop_bool(props, "locked", False)
    prop_str(props, "name", name)
    prop_int(props, "orientation", 0)
    prop_bool(props, "outline", True)
    prop_int(props, "outlineStyle", 1)
    prop_int(props, "pointerPriority", 0)
    prop_int(props, "shape", 1)
    prop_bool(props, "visible", True)
    SubElement(node, "values")
    value_slot(node, "touch", "false")
    return node


def make_label(text: str, frame: tuple[float, float, float, float]) -> Element:
    node = common_node("LABEL", f"lbl_{text}", frame, (0.15, 0.15, 0.15, 1), interactive=False)
    props = node.find("properties")
    assert props is not None
    prop_int(props, "font", 0)
    prop_int(props, "textAlignH", 2)
    prop_int(props, "textAlignV", 2)
    prop_bool(props, "textClip", True)
    prop_color(props, "textColor", (1, 1, 1, 1))
    prop_int(props, "textLength", 0)
    prop_int(props, "textSize", 14)
    value_slot(node, "text", text, locked_default_current=1)
    return node


def make_fader(
    name: str,
    label: str,
    address: str,
    lo: float,
    hi: float,
    color: tuple[float, float, float, float],
    frame: tuple[float, float, float, float],
) -> list[Element]:
    x, y, w, h = frame
    nodes = [make_label(label, (x, y - 28, w, 26))]
    fader = common_node("FADER", name, frame, color)
    props = fader.find("properties")
    assert props is not None
    prop_bool(props, "bar", True)
    prop_int(props, "barDisplay", 0)
    prop_bool(props, "cursor", True)
    prop_int(props, "cursorDisplay", 0)
    prop_bool(props, "grid", False)
    prop_int(props, "gridSteps", 1)
    prop_int(props, "response", 0)
    prop_int(props, "responseFactor", 100)
    prop_bool(props, "centered", False)
    value_slot(fader, "x", "0")
    osc_message(fader, address, scale_min=lo, scale_max=hi)
    nodes.append(fader)
    return nodes


def make_button(
    name: str,
    label: str,
    address: str,
    frame: tuple[float, float, float, float],
    color: tuple[float, float, float, float],
    *,
    toggle: bool,
    scale_min: float = 0.0,
    scale_max: float = 1.0,
) -> list[Element]:
    x, y, w, h = frame
    nodes = [make_label(label, (x, y - 24, w, 22))]
    # buttonType: 0=MOMENTARY, 2=TOGGLE_PRESS
    btn = common_node("BUTTON", name, frame, color)
    props = btn.find("properties")
    assert props is not None
    prop_int(props, "buttonType", 2 if toggle else 0)
    prop_bool(props, "press", True)
    prop_bool(props, "release", True)
    prop_bool(props, "valuePosition", False)
    value_slot(btn, "x", "0")
    osc_message(btn, address, scale_min=scale_min, scale_max=scale_max)
    nodes.append(btn)
    return nodes


def make_page_group(name: str, tab_label: str) -> Element:
    page = common_node("GROUP", name, (0, 0, W, H - 48), (0.08, 0.08, 0.1, 1), interactive=False)
    props = page.find("properties")
    assert props is not None
    prop_bool(props, "tabLabel", True)
    prop_str(props, "name", tab_label)
    prop_color(props, "tabColorOff", (0.2, 0.2, 0.22, 1))
    prop_color(props, "tabColorOn", (0.35, 0.45, 0.75, 1))
    prop_color(props, "textColorOff", (0.8, 0.8, 0.8, 1))
    prop_color(props, "textColorOn", (1, 1, 1, 1))
    SubElement(page, "children")
    return page


def add_children(parent: Element, kids: list[Element]) -> None:
    children = parent.find("children")
    if children is None:
        children = SubElement(parent, "children")
    for kid in kids:
        children.append(kid)


def build_performance_page() -> Element:
    page = make_page_group("page_performance", "Performance")
    kids: list[Element] = [make_label("Pixel Fun 3D", (20, 12, 360, 28))]

    n = len(FADERS)
    margin = 24
    gap = 10
    usable = W - 2 * margin
    col_w = (usable - gap * (n - 1)) / n
    fader_h = 480
    fader_y = 70

    for i, (name, label, address, lo, hi, color) in enumerate(FADERS):
        x = margin + i * (col_w + gap)
        kids.extend(make_fader(name, label, address, lo, hi, color, (x, fader_y, col_w, fader_h)))

    row_y = fader_y + fader_h + 40
    btn_w, btn_h = 150, 72
    x = margin
    kids.extend(
        make_button(
            "freeze",
            "Freeze",
            "/pixelfun3d/time_frozen",
            (x, row_y, btn_w, btn_h),
            (0.95, 0.55, 0.15, 1),
            toggle=True,
        )
    )
    x += btn_w + 18
    kids.extend(
        make_button(
            "direction",
            "Dir 0=fwd",
            "/pixelfun3d/time_direction",
            (x, row_y, btn_w, btn_h),
            (0.95, 0.85, 0.2, 1),
            toggle=True,
        )
    )
    x += btn_w + 18
    kids.extend(
        make_button(
            "panic",
            "PANIC",
            "/pixelfun3d/panic",
            (x, row_y, btn_w, btn_h),
            (0.9, 0.15, 0.15, 1),
            toggle=False,
        )
    )
    x += btn_w + 18
    kids.extend(
        make_button(
            "sync",
            "Sync",
            "/pixelfun3d/config",
            (x, row_y, btn_w, btn_h),
            (0.45, 0.45, 0.5, 1),
            toggle=False,
        )
    )

    add_children(page, kids)
    return page


def build_scenes_page() -> Element:
    page = make_page_group("page_scenes", "Scenes")
    kids: list[Element] = [make_label("Scenes — press to fire", (20, 12, 420, 28))]

    cols, rows = 4, 2
    margin = 40
    gap = 20
    top = 70
    usable_w = W - 2 * margin
    usable_h = H - top - 60
    bw = (usable_w - gap * (cols - 1)) / cols
    bh = (usable_h - gap * (rows - 1)) / rows

    for i, (slug, title) in enumerate(SCENES):
        c, r = i % cols, i // cols
        x = margin + c * (bw + gap)
        y = top + r * (bh + gap)
        kids.extend(
            make_button(
                f"sc_{slug}",
                title,
                f"/pixelfun3d/scenes/{slug}/fire",
                (x, y, bw, bh),
                (0.45, 0.3, 0.75, 1),
                toggle=False,
            )
        )

    add_children(page, kids)
    return page


def build_root() -> Element:
    root = Element("lexml", version="3")
    group = common_node("GROUP", "pixelfun3d_v1", (0, 0, W, H), (0.05, 0.05, 0.07, 1), interactive=False)
    # Project-ish name on root group
    props = group.find("properties")
    assert props is not None
    prop_str(props, "name", "pixelfun3d-v1")

    pager = common_node("PAGER", "pages", (0, 0, W, H), (0.12, 0.12, 0.14, 1), interactive=True)
    pprops = pager.find("properties")
    assert pprops is not None
    prop_bool(pprops, "tabLabels", True)
    prop_bool(pprops, "tabbar", True)
    prop_bool(pprops, "tabbarDoubleTap", False)
    prop_int(pprops, "tabbarSize", 48)
    prop_int(pprops, "textSizeOff", 16)
    prop_int(pprops, "textSizeOn", 16)
    value_slot(pager, "page", "0")

    add_children(pager, [build_performance_page(), build_scenes_page()])
    add_children(group, [pager])
    root.append(group)
    return root


def main() -> None:
    root = build_root()
    xml_bytes = tostring(root, encoding="utf-8", xml_declaration=True)
    XML_OUT.write_bytes(xml_bytes)
    TOSC_OUT.write_bytes(zlib.compress(xml_bytes))
    print(f"Wrote {XML_OUT}")
    print(f"Wrote {TOSC_OUT}")


if __name__ == "__main__":
    main()
