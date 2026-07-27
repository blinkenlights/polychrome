# Pixelfun Controller Roadmap

Plan zur Steuerung von **Pixel Fun 3D** über externe Controller — zuerst TouchOSC, danach Korg NanoKontrol und Novation Launchpad.

**Scope:** nur Pixel Fun 3D (Live-Performance bei Electro-Sets). Andere Apps ausgeklammert. Pixel Fun 2D ist kein Primärziel.

**Ausgangslage (Ist):**

- Octopus hat bereits einen **OSC-Server** (UDP, typisch Port 8000).
- Generische OSC-Pfade `[prefix, key]` schreiben heute nur in `Octopus.Params` und echoen an Clients.
- Pixel Fun 3D hat `use Octopus.Params, prefix: :pixelfun3d` mit wenigen gelesenen Params (`time_scale`, `easing_interval`, `value_percent`).
- Die live relevanten Look-Regler sind **Tweakables / App-Config** (`zoom_base`, `roll_rate`, …) — **noch nicht** über denselben OSC→Tweakable-Pfad angebunden.
- `Params.Global.speed` und `Params.Global.brightness` sind bereits per `/global/...` OSC erreichbar.
- MIDI-Eingang für Controller fehlt (→ Phase 3).

---

## Ziele (gesamt)

1. Pixel Fun 3D live performen ohne Web-Console als Primary Surface.
2. Klarer Action-/Adress-Satz.
3. Zuerst OSC (TouchOSC), danach MIDI auf dieselben Actions.
4. Keine Device-Logik in `pixel_fun_3d.ex`.
5. Soft takeover + UI-Sync bereits in Phase 1.

---

## Fachbegriffe

| Begriff | Bedeutung |
|--------|-----------|
| **Parameter / Tweakable** | Einstellwert von Pixel Fun 3D |
| **Scene / Preset / Mode** | Gespeicherter Look unter `app_mode_presets/pixelfun3d/` |
| **OSC** | Netzwerk-Steuerprotokoll mit Adressen und Floats |
| **MIDI** | Hardware-Protokoll (Notes/CCs); ab Phase 3 |
| **Ingress** | Eingang: externe Signale → interne Actions |
| **Egress / Feedback / UI-Sync** | Rückweg: Ist-Werte → TouchOSC (Phase 1) bzw. Launchpad-LEDs (Phase 3) |
| **Soft takeover / Pickup** | Fader greift erst, wenn er den aktuellen Ist-Wert überfährt |
| **Harter Cut** | Scene wird sofort angewendet, kein Crossfade |

### MIDI vs. OSC

- **OSC:** vorhandener Netzwerkkanal, benannte Adressen → Phase 1.
- **MIDI:** nativ an Nano/Launchpad → Phase 3, mappt auf dieselben Actions.

---

## Architektur-Zielbild

```text
[TouchOSC] ──OSC──┐
[NanoKontrol]─MIDI─┼──► Ingress ──► Binding/Profile ──► Pixelfun3D Actions
[Launchpad]──MIDI──┘                                      │
                                                          ▼
                                    Tweakables / Params.Global / Scenes
                                    (+ Soft takeover + UI-Sync)
```

---

## Phase 0 — Entscheidungen (geschlossen)

| # | Thema | Entscheidung |
|---|--------|--------------|
| 1 | Operator | Live-Performance bei Electro-Sets |
| 2 | Ohne Laptop / Dunkel | Ziel ja; taktil/blind vor allem **Phase 3**. Phase 1 = TouchOSC statt Web-Console |
| 3 | Hardware-Feedback | Launchpad-LEDs **Phase 3**. TouchOSC UI-Sync **Phase 1** |
| 4 | Soft takeover | **Ja, Phase 1** (Pickup) |
| 5 | App | **Pixel Fun 3D** |
| 6 | OSC-Auth | erstmal ohne; **Phase 4** |
| Speed-Fader | ein Fader = **`Params.Global.speed`** |
| Brightness-Fader | ein Fader = **`brightness_percent`** (Scene) |
| Legacy `time_scale` / `value_percent` | im Performance-Desk **unsichtbar** (intern default 1.0 / 100) |
| UI-Sync | **ja** (TouchOSC bekommt Ist-Werte) |
| Scene-Fire | **harter Cut** |
| Scene-Bank | **8 kuratierte Slugs** (vorläufig, austauschbar) — siehe Phase 1 §6 |
| Autos bei Scene-Fire | Motion-/Transform-/Sat-Autos **forciert aus**; **`palette_auto` wie im Preset** |
| Momentary | **nicht** Phase 1 |
| Panic | Freeze + Motion 0; **Brightness unverändert** |
| Blackout-Button | **nein** |
| OSC-Prefix | **`/pixelfun3d/`** |
| OSC-Werte | **App-Einheiten** (nicht normiert 0…1); TouchOSC skaliert clientseitig |
| `time_direction` | **String** `"forward"` / `"backward"` |
| Globals | **`/global/speed`**, **`/global/brightness`** ansprechbar (Brightness-Global nicht auf Primary-Bank) |
| Web-Console | **parallel erlaubt**; Sync + Soft takeover gelten auch dafür |

### Speed- / Brightness-Schichten (Referenz)

```text
Zeitfortschritt  ∝  time_scale × Global.speed × time_direction
Formel-t         =  seconds × pattern_speed

Pixelfun-Gain    =  value_percent × brightness_percent / 100
Global.brightness → Broadcaster.set_luminance (Installation 0…255)
```

Desk v1 nutzt nur **Global.speed** und **brightness_percent**.

---

## Phase 1 — Spezifikation (TouchOSC)

### Implementierungsfortschritt

| Scheibe | Inhalt | Status |
|--------:|--------|--------|
| 1 | OSC → Tweakables/Globals (Primary Fader/Toggles, Console-Pfad) | **done** |
| 2 | Scene-Fire + Panic | **done** |
| 3 | Soft takeover + UI-Sync | **done** |
| 4 | TouchOSC-Layout + Operator-Notiz | pending |

**Scheibe 1 geliefert:** `Octopus.Osc.Pixelfun3D` + Routing in `Osc.Server`. Continuous/Toggles gehen über `InstallationTransport.set_tweakable/2`. Legacy Params bleiben `Params.put`. `/global/speed` unverändert.

**Scheibe 2 geliefert:** `/pixelfun3d/scenes/<slug>/fire` → `play_now` + discard overrides + Motion/Sat-Autos forciert aus (`palette_auto` aus Preset). `/pixelfun3d/panic` → Freeze + Motion 0, Brightness unverändert. Trigger nur auf Press (`1`/`1.0`), Release ignoriert.

**Scheibe 3 geliefert:** `Octopus.Osc.SoftTakeover` (Pickup pro Client+Param), `Octopus.Osc.UiSync` (Performance-Bank inkl. `/global/speed`). Osc.Server subscribed `installation_transport` + `global_params`, pusht Bundles an Clients und markiert sie matched. Neuer Client / `/pixelfun3d/config` triggert Sync. Continuous ohne Pickup → `:held`.

### Ziel

Pixel Fun 3D über TouchOSC live spielbar: Continuous Controls, Toggles, kuratierte Scenes, Panic; mit Soft takeover und UI-Sync. Web-Console bleibt parallel nutzbar.

### Nicht in Phase 1

- MIDI / Nano / Launchpad
- Momentary holds
- Crossfade zwischen Scenes
- OSC-Auth
- `pattern_speed` / Global Brightness als Primary-Fader (optional später Advanced)
- Automation-Recording

---

### 1. OSC-Adressschema v1

#### Continuous (Float in **App-Einheiten**; TouchOSC skaliert 0…1 → Range clientseitig)

| Adresse | Ziel | Range (App) | Soft takeover |
|---------|------|-------------|---------------|
| `/global/speed` | `Params.Global.speed` | 0.01 … 10 (exp wie Console) | ja |
| `/pixelfun3d/brightness_percent` | Scene brightness | 0 … 100 | ja |
| `/pixelfun3d/zoom_base` | Zoom | 0.7 … 11 | ja |
| `/pixelfun3d/roll_rate` | Rotation °/s | −180 … 180 | ja |
| `/pixelfun3d/orbit_rate` | Translate X | −30 … 30 | ja |
| `/pixelfun3d/elev_base` | Translate Y | −4 … 4 | ja |
| `/pixelfun3d/tilt_scale` | Sway | 0 … 4 | ja |
| `/pixelfun3d/saturation_percent` | Saturation | 0 … 100 | ja |
| `/pixelfun3d/color_interval` | Color tempo (s) | 1 … 120 | ja |
| `/pixelfun3d/bleeding` | Bleeding | 0 … 100 | ja |

`/global/brightness` bleibt technisch erreichbar (existierender Pfad), liegt aber **nicht** auf der Primary-TouchOSC-Bank.

#### Discrete / Actions

| Adresse | Verhalten |
|---------|-----------|
| `/pixelfun3d/time_frozen` | Toggle/Set (0/1 oder bool) |
| `/pixelfun3d/time_direction` | String-Argument `"forward"` oder `"backward"` |
| `/pixelfun3d/panic` | Panic auslösen (Trigger, z. B. Arg `1`) |
| `/pixelfun3d/scenes/<slug>/fire` | Scene harter Cut |

#### UI-Sync / Egress (Phase 1)

- Nach jeder akzeptierten Änderung (OSC **oder** Console): Ist-Werte an bekannte OSC-Clients pushen (gleiche Adressen).
- Nach Scene-Fire: alle Continuous + relevanten Toggles der Performance-Bank syncen.
- Optional: `/pixelfun3d/config` (oder vorhandenes `/config` erweitern) zum Full-Dump für TouchOSC-Connect.

Legacy `/pixelfun3d/time_scale`, `/pixelfun3d/value_percent`, `/pixelfun3d/easing_interval` bleiben technisch über Params nutzbar, erscheinen **nicht** im TouchOSC-Layout.

---

### 2. Soft takeover (Pickup)

- Pro Continuous-Binding hält der Server den **armed/matched**-Status pro Client (oder global pro Param — bei Implementierung wählen; Empfehlung: **pro Param global**, einfacher).
- Eingehender Faderwert wird **ignoriert**, bis er den aktuellen Ist-Wert überfährt/erreicht (mit kleinem Epsilon).
- Danach: matched → Werte werden angewendet; UI-Sync hält Fader und Reality aligned.
- Scene-Fire und Console-Änderungen setzen betroffene Params wieder auf **unmatched**, bis Pickup erneut greift — **außer** UI-Sync setzt den Client-Fader auf den Ist-Wert; dann ist der Client sofort matched, wenn TouchOSC den Sync übernimmt.
- **Gewünschte Operator-Erfahrung mit UI-Sync:** nach Scene-Fire springen TouchOSC-Fader auf die Preset-Werte → sofort spielbar ohne Blind-Pickup. Soft takeover greift vor allem bei **Desync** (Console parallel, zweiter Client, Sync verloren).

---

### 3. Scene-Fire

1. Harter Cut über bestehenden Mode-/Preset-Pfad (`apply_mode` / `InstallationTransport.play_now` — konkreter Call bei Implementierung am bestehenden Console-Pfad ausrichten).
2. Danach **Motion-/Transform-/Sat-Autos forciert aus:**
   - `trans_auto`, `rot_auto`, `zoom_auto`, `sway_auto`, `sat_auto` → `false`
3. **`palette_auto` bleibt wie im Preset** (nicht überschreiben).
4. UI-Sync der Performance-Bank.
5. Continuous Controls: Soft-Takeover-State wie oben.

---

### 4. Panic

Trigger `/pixelfun3d/panic`:

- `time_frozen` → `true`
- Motion auf 0: zumindest `roll_rate`, `orbit_rate`, `elev_base`, `tilt_scale` → `0`
- Autos aus (gleiche Liste wie Scene-Fire)
- **Brightness unverändert**
- kein separater Blackout
- UI-Sync danach

---

### 5. Primary TouchOSC-Layout (Inhalt)

**Seite A — Performance**

- Fader: Speed (global), Brightness, Zoom, Rotation, Translate X, Translate Y, Sway, Saturation, Color tempo, Bleeding  
- Toggles: Freeze, Time direction, Panic  

**Seite B — Scenes**

- 8 Buttons für die kuratierte Bank (§6)

Kein Momentary in v1.

---

### 6. Kuratierte Scene-Bank (vorläufig, austauschbar)

| # | slug | name |
|---|------|------|
| 1 | `classic_ripple` | Classic ripple |
| 2 | `nordlicht` | Nordlicht |
| 3 | `doppelhelix` | Doppelhelix |
| 4 | `leuchtplankton` | Leuchtplankton |
| 5 | `sternenhimmel` | Sternenhimmel |
| 6 | `marmor` | Marmor |
| 7 | `strudel` | Strudel |
| 8 | `nebelringe` | Nebelringe |

OSC: `/pixelfun3d/scenes/<slug>/fire`  
Vollständige Preset-Liste bleibt in `pixelfun3d-settings.json`; nur diese acht liegen auf TouchOSC Seite B.

---

### 7. Implementierungsrichtung (ohne Device-Logik in der App)

1. **OSC-Ingress erweitern** (`Osc.Server`): `/pixelfun3d/<tweakable>` und `/pixelfun3d/scenes/.../fire` / `panic` nicht nur als stummes `Params.put`, sondern in einen kleinen **Pixelfun3D-Control**-Pfad (Tweakables setzen wie die Console).
2. **`/global/speed`** weiter über bestehenden `Params.Global`-Handler; Soft takeover auch dort anbinden, wenn der Fader auf dem Desk liegt.
3. **Eine Schreibquelle für Tweakables** mit Console teilen (`InstallationTransport.set_tweakable` / bestehender Console-Äquivalent-Pfad — bei Implementierung den tatsächlichen Console-Call nachziehen, keine Parallelwelt).
4. **UI-Sync:** Clients, die der OSC-Server schon trackt, mit Ist-Werten beliefern (ähnlich heutiges Echo/`/config`).
5. **TouchOSC-Layout-Datei** + kurze Operator-Notiz im Repo (`docs/` oder `octopus/priv/...`).
6. Kein Nano/Launchpad-Code.

Konkrete Module/Funktionssignaturen werden bei der Implementierung am Code festgemacht — dieser Plan legt Verhalten und Adressen fest, nicht jeden Dateinamen.

---

### 8. Deliverables Phase 1

1. Dokumentiertes OSC-Schema (dieses Kapitel, ggf. als eigene `docs/pixelfun3d-osc.md` extrahiert).
2. Server-Support: Continuous + Toggles + Scene-Fire + Panic + Soft takeover + UI-Sync.
3. Autos bei Scene-Fire forciert aus (Motion/Transform/Sat-Auto); `palette_auto` aus Preset.
4. TouchOSC-Layout v1 (Seite Performance + Seite Scenes mit 8 Slugs).
5. Kuratierte Scene-Liste (Config/Datei; vorläufig §6).
6. Operator-Notiz (Adressen, Ranges, Panic, Soft takeover).
7. Manueller Testplan abgehakt (siehe Akzeptanz).

---

### 9. Akzeptanzkriterien

- [ ] Alle Primary-Fader ändern Pixel Fun 3D live über TouchOSC (App-Einheiten).
- [ ] Global Speed-Fader ändert `Params.Global.speed`.
- [ ] Die 8 kuratierten Scene-Buttons feuern Presets (harter Cut).
- [ ] Nach Scene-Fire sind `trans_auto` / `rot_auto` / `zoom_auto` / `sway_auto` / `sat_auto` aus; `palette_auto` entspricht dem Preset.
- [ ] `time_direction` akzeptiert `"forward"` / `"backward"`.
- [ ] TouchOSC-Fader/Toggles zeigen nach Fire/Console-Änderung die Ist-Werte (UI-Sync).
- [ ] Bei Desync greift Pickup (kein harter Sprung beim ersten Fader-Touch außerhalb des Ist-Werts).
- [ ] Panic: Freeze + Motion 0, Brightness unverändert, UI-Sync.
- [ ] Web-Console parallel: Änderung dort reflektiert sich in TouchOSC; Soft takeover bleibt konsistent.
- [ ] Keine Nano/Launchpad-/MIDI-Abhängigkeiten.
- [ ] Legacy-Params nicht auf dem Layout.

---

### 10. Phase-1-Spezifikation

**Geschlossen.** Bereit zur Implementierung. Scene-Bank (§6) ist vorläufig und jederzeit austauschbar.

---

## Phase 2 — Action-Layer & Mapping-Modell

Phase-1-OSC-Handler in deklarative Actions/Bindings ziehen, damit MIDI denselben Kern trifft. Soft takeover bleibt im gemeinsamen Pfad.

---

## Phase 3 — MIDI: NanoKontrol & Launchpad

Hardware-Ingress; Dunkel-Desk; Launchpad-LED-Feedback. TouchOSC bleibt parallel.

| Gerät | Rolle |
|-------|--------|
| NanoKontrol | Continuous Performance |
| Launchpad | Scenes + LED-Feedback |

---

## Phase 4 — Härtung (vormerken)

- OSC-Auth / Netzwerk-Härtung
- optional Link/Clock, Preset-Save, Multi-Controller-Locks

---

## Reihenfolge

| Phase | Fokus |
|------:|-------|
| 0 | Entscheidungen (geschlossen) |
| 1 | TouchOSC + OSC + Soft takeover + UI-Sync (**spezifiziert**) |
| 2 | Action/Mapping-Layer |
| 3 | MIDI Nano + Launchpad + LEDs |
| 4 | Auth / Show-Ops |

---

## Risiken

1. OSC schreibt nur Params, Console schreibt Tweakables → **muss** ein Schreibpfad werden.
2. UI-Sync + Soft takeover + parallele Console → State-Maschine klar halten (matched/unmatched).
3. Scene-Fire überschreibt Looks → UI-Sync ist Pflicht für gute UX.
4. `Hardware.Controller` ≠ MIDI-Controller (Naming).

---

## Bezug im Repo

- App: `octopus/lib/octopus/apps/pixel_fun_3d.ex`
- Presets: `octopus/priv/app_mode_presets/pixelfun3d/pixelfun3d-settings.json`
- OSC: `octopus/lib/octopus/osc/server.ex`
- Global Params: `octopus/lib/octopus/params/global.ex`
- Transport/Tweakables: `octopus/lib/octopus/installation_transport.ex`
- Formel-Notizen: `docs/pixelfun.md`
