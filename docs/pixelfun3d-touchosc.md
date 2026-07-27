# Pixel Fun 3D — TouchOSC Operator Guide

Live-Performance surface for Octopus / Pixel Fun 3D (Phase 1).

## Where is the interface?

| Artifact | Path | What it is |
|----------|------|------------|
| **This guide** | `docs/pixelfun3d-touchosc.md` | Addresses, ranges, connection, behaviour |
| **Layout blueprint** | `octopus/priv/touchosc/pixelfun3d-v1.json` | Machine-readable control map |
| **TouchOSC file** | `octopus/priv/touchosc/pixelfun3d-v1.touchosc` | Importable layout (TouchOSC **Mk1** format; also opens in many Mk2 workflows via import — see below) |

There is no in-browser TouchOSC UI. The desk lives in the **TouchOSC app** after you load the layout.

### Open the layout

1. Install [TouchOSC](https://hexler.net/touchosc) (desktop or mobile).
2. Open / import `octopus/priv/touchosc/pixelfun3d-v1.touchosc`.
   - **Mk1 editor / legacy:** File → Open.
   - **Mk2:** try *Open* / *Import*; if your build rejects Mk1 files, recreate from the blueprint JSON (same addresses) — about 15 minutes in the editor.
3. Connection → **UDP** → Host = machine running Octopus → Port **`8000`**.
4. Enable **OSC feedback / receiving** so UI-Sync can move faders after scene changes.
5. In the Octopus installation console: put **Pixel Fun 3D** now-playing.

Optional: send `/pixelfun3d/config` with `1` (Sync button on the layout) to force a full performance-bank push.

---

## Connection

| Setting | Value |
|---------|--------|
| Protocol | UDP |
| Port | `8000` (`:osc_server_port`) |
| Disable server | `OSC_SERVER_ENABLED=false` |
| Auth | none (Phase 4 later) |

Octopus echoes/pushes to OSC clients it has recently heard from (first packet registers the client).

---

## Page A — Performance

Values are **app units** (not 0…1). Soft takeover applies to continuous faders.

| Control | OSC address | Range / args | Notes |
|---------|-------------|--------------|--------|
| Speed | `/global/speed` | 0.01 … 10 | Global; soft takeover |
| Brightness | `/pixelfun3d/brightness_percent` | 0 … 100 | Scene brightness |
| Zoom | `/pixelfun3d/zoom_base` | 0.7 … 11 | |
| Rotation | `/pixelfun3d/roll_rate` | −180 … 180 | °/s |
| Translate X | `/pixelfun3d/orbit_rate` | −30 … 30 | |
| Translate Y | `/pixelfun3d/elev_base` | −4 … 4 | |
| Sway | `/pixelfun3d/tilt_scale` | 0 … 4 | |
| Saturation | `/pixelfun3d/saturation_percent` | 0 … 100 | |
| Color tempo | `/pixelfun3d/color_interval` | 1 … 120 | seconds |
| Bleeding | `/pixelfun3d/bleeding` | 0 … 100 | |
| Freeze | `/pixelfun3d/time_frozen` | `0` / `1` | toggle |
| Direction | `/pixelfun3d/time_direction` | `0`=forward, `1`=backward **or** strings `"forward"` / `"backward"` | |
| Panic | `/pixelfun3d/panic` | press `1` | Freeze + motion 0; brightness unchanged |
| Sync | `/pixelfun3d/config` | press `1` | Push Ist-Werte to this client |

Legacy (not on layout): `/pixelfun3d/time_scale`, `/pixelfun3d/value_percent`, `/pixelfun3d/easing_interval`.

---

## Page B — Scenes

Press = `1` (release `0` ignored). Hard cut; motion/sat autos forced off; `palette_auto` kept from preset.

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

Any other known `pixelfun3d` slug also works on the server; only these eight are on the layout.

---

## Behaviour cheat sheet

- **Soft takeover:** If a fader is far from the live value, moves are ignored until you hit the Ist-Wert (pickup). After UI-Sync, the client is marked matched → immediately playable.
- **UI-Sync:** Console tweaks, scene fire, panic, and global speed changes push the performance bank to registered OSC clients.
- **Panic:** Freezes time, zeros roll/orbit/elev/sway, clears motion autos; does **not** dim brightness.
- **Parallel console:** Allowed; sync + soft takeover still apply.

---

## Wireframe

```text
┌─ Performance ──────────────────────────────────────────┐
│ Speed Bright Zoom Rot  TX   TY  Sway Sat  Tempo Bleed │
│  ║     ║     ║    ║    ║    ║    ║    ║     ║     ║   │
│  ║     ║     ║    ║    ║    ║    ║    ║     ║     ║   │
│  ║     ║     ║    ║    ║    ║    ║    ║     ║     ║   │
│ Freeze  Direction  [PANIC]  [SYNC]                      │
└────────────────────────────────────────────────────────┘

┌─ Scenes ───────────────────────────────────────────────┐
│ [Classic] [Nordlicht] [Doppelhelix] [Leuchtplankton]   │
│ [Sterne]  [Marmor]    [Strudel]     [Nebelringe]       │
└────────────────────────────────────────────────────────┘
```

---

## IEx smoke test (without TouchOSC)

```elixir
Octopus.Osc.Pixelfun3D.handle(["scenes", "marmor", "fire"], [1.0])
Octopus.Osc.Pixelfun3D.handle(["zoom_base"], [2.5])  # may :held until pickup / sync
Octopus.Osc.Pixelfun3D.handle(["panic"], [1.0])
```

---

## Rebuild the `.touchosc` file

```bash
python3 octopus/priv/touchosc/build_mk1_layout.py
```

Writes `pixelfun3d-v1.touchosc` next to the script (stdlib only, no pip).
