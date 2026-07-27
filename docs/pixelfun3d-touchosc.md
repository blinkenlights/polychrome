# Pixel Fun 3D — TouchOSC Operator Guide

Live-Performance surface for Octopus / Pixel Fun 3D (Phase 1).

**Target app:** TouchOSC **Mk2** (e.g. **1.5.2**).

## Where is the interface?

| Artifact | Path | What it is |
|----------|------|------------|
| **Mk2 XML** | `octopus/priv/touchosc/pixelfun3d-v1.xml` | Preferred for 1.5.x — File → Open / Import |
| **Mk2 `.tosc`** | `octopus/priv/touchosc/pixelfun3d-v1.tosc` | Native Mk2 project (same content, zlib) |
| **This guide** | `docs/pixelfun3d-touchosc.md` | Addresses, ranges, connection |
| **Blueprint** | `octopus/priv/touchosc/pixelfun3d-v1.json` | Optional control map (not needed to play) |

There is no in-browser TouchOSC UI. Load the layout in the **TouchOSC** app.

### Open in TouchOSC 1.5.2 (Mk2)

1. Open [TouchOSC](https://hexler.net/touchosc) 1.5.x.
2. **File → Open** (or Import)  
   - `octopus/priv/touchosc/pixelfun3d-v1.xml` **or**  
   - `octopus/priv/touchosc/pixelfun3d-v1.tosc`
3. Connections → **OSC** → **UDP** → Host = machine running Octopus → Port **`8000`**.
4. Enable **receive / feedback** on the OSC connection so UI-Sync can move faders.
5. In Octopus: put **Pixel Fun 3D** now-playing.

Optional: tap **Sync** on the Performance page (`/pixelfun3d/config` = `1`) to force a bank push.

Faders send **app units** (TouchOSC scales 0…1 ↔ min/max in the layout). Same scaling is used on receive.

### Rebuild

```bash
python3 octopus/priv/touchosc/build_mk2_layout.py
```

Writes both `.xml` and `.tosc`.

---

## Connection

| Setting | Value |
|---------|--------|
| Protocol | UDP |
| Port | `8000` (`:osc_server_port`) |
| Disable server | `OSC_SERVER_ENABLED=false` |
| Auth | none (Phase 4 later) |

Octopus pushes to OSC clients it has recently heard from (first packet registers the client).

---

## Page A — Performance

Soft takeover applies to continuous faders.

| Control | OSC address | Range / args | Notes |
|---------|-------------|--------------|--------|
| Speed | `/global/speed` | 0.01 … 10 | Global |
| Brightness | `/pixelfun3d/brightness_percent` | 0 … 100 | Scene |
| Zoom | `/pixelfun3d/zoom_base` | 0.7 … 11 | |
| Rotation | `/pixelfun3d/roll_rate` | −180 … 180 | °/s |
| Translate X | `/pixelfun3d/orbit_rate` | −30 … 30 | |
| Translate Y | `/pixelfun3d/elev_base` | −4 … 4 | |
| Sway | `/pixelfun3d/tilt_scale` | 0 … 4 | |
| Saturation | `/pixelfun3d/saturation_percent` | 0 … 100 | |
| Color tempo | `/pixelfun3d/color_interval` | 1 … 120 | seconds |
| Bleeding | `/pixelfun3d/bleeding` | 0 … 100 | |
| Freeze | `/pixelfun3d/time_frozen` | `0` / `1` | toggle |
| Direction | `/pixelfun3d/time_direction` | `0`=forward, `1`=backward | toggle |
| Panic | `/pixelfun3d/panic` | press `1` | Freeze + motion 0 |
| Sync | `/pixelfun3d/config` | press `1` | Push Ist-Werte |

Legacy (not on layout): `/pixelfun3d/time_scale`, `/pixelfun3d/value_percent`, `/pixelfun3d/easing_interval`.

---

## Page B — Scenes

Press = `1` (release ignored). Hard cut; motion/sat autos forced off; `palette_auto` from preset.

| Button | OSC address |
|--------|-------------|
| Classic ripple | `/pixelfun3d/scenes/classic_ripple/fire` |
| Nordlicht | `/pixelfun3d/scenes/nordlicht/fire` |
| Doppelhelix | `/pixelfun3d/scenes/doppelhelix/fire` |
| Leuchtplankton | `/pixelfun3d/scenes/leuchtplankton/fire` |
| Sternenhimmel | `/pixelfun3d/scenes/sternenhimmel/fire` |
| Marmor | `/pixelfun3d/scenes/marmor/fire` |
| Strudel | `/pixelfun3d/scenes/strudel/fire` |
| Nebelringe | `/pixelfun3d/scenes/nebelringe/fire` |

---

## Behaviour cheat sheet

- **Soft takeover:** Fader far from live value → ignored until pickup. After UI-Sync, client is matched.
- **UI-Sync:** Console / scene / panic / global speed push the performance bank.
- **Panic:** Freeze + zero motion; brightness unchanged.
- **Parallel console:** Allowed.

---

## Mk1 vs Mk2 (short)

| | Mk1 (legacy) | Mk2 (current, 1.5.x) |
|--|--|--|
| Files | `.touchosc` (ZIP) | `.tosc` / **XML** |
| This repo | removed | `pixelfun3d-v1.xml` + `.tosc` |
