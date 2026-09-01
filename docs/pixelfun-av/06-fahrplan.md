# 06 — Fahrplan

Reihenfolge nach einem Prinzip: **Das entscheidende Erlebnis zuerst, die schöne
Oberfläche danach.** Die ersten drei Schritte haben kein UI und liefern trotzdem den
Moment, an dem das Projekt real wird. Andersherum baut man zwei Wochen an einer
Oberfläche und merkt dann, dass sich die Kopplung anders anfühlt als gedacht.

## M0 · Ton aus dem Server ✅

`Octopus.Sound`-Supervisor, das `Sound.Engine`-Behaviour und ein erstes Backend.
Bedienbar aus IEx, sonst nichts.

- `Sound.Engine` (Behaviour), `Sound.Engine.Beak` bzw. `Sound.Engine.SuperCollider`
- `Sound.panic/0`

**Fertig.** `Octopus.Sound` ist aus IEx bedienbar, `Octopus.Sound.Engine` hat drei
Backends (Null, Beak, SuperCollider), SynthDefs liegen in `priv/synthdefs`.

> Welches Backend zuerst, ist eine reine Praxisfrage: Auf dem Zielrechner ist beak
> gesetzt (läuft schon). Auf einem Mac zum Entwickeln ist SuperCollider vermutlich
> schneller startklar (`brew install --cask supercollider`), während beak erst gebaut
> werden muss — das CMake-Setup ist auf Apple vorbereitet, aber ungetestet. Das
> Behaviour macht daraus eine Konfigurationszeile, keine Weggabelung.

## M1 · Die Uhr ✅

`Sound.Clock` (BPM, Play/Stop, Position, PubSub-Broadcast der Beat-Phase) und
`Sound.Scheduler` mit Look-ahead-Fenster.

**Fertig.** `Sound.Timeline` (rein, getestet), `Sound.Clock` und `Sound.Scheduler`
mit 200-ms-Vorlauf. Gemessen: nach vier Sekunden bei 120 BPM steht der Transport auf
8,002 Beats. 28 Tests decken Uhr, Scheduler und OSC-Kodierung ab.

## M2 · Probes in Pixelfun ✅

Kleiner, klar abgegrenzter Eingriff in `pixel_fun.ex`: hinter einem Schalter pro Frame
zusätzlich N Punkte auswerten und als `{:pixel_probes, %{t_beats: _, values: [...]}}`
broadcasten.

**Fertig.** `PixelFun.probe_values/1` wertet die Formel an der Mitte jedes Panels aus,
`Octopus.Sound.Probes` verteilt sie pro Frame. Die Flat-Transformparameter liegen jetzt
in einer eigenen Funktion, damit Probe und Bild nicht auseinanderlaufen können.

## M3 · Ring-Chase — das erste audiovisuelle Ergebnis ✅

Der Scheduler verbindet Probes mit Tönen: Nulldurchgang an Panel n → kurzer Ton auf
Kanal n. Formel und Klang zunächst fest verdrahtet.

**Fertig.** `Octopus.Sound.RingChase` spielt das Panel, dessen Wert durch null steigt.
Gemessen mit `sin(x*0.5 - t)` auf Nation2026: die Panels klingen in der Reihenfolge
10, 11, 12, 1, 2, 3, 4, 5, 6, 7, 8 — einmal um den Ring und über die Naht.

Zwei Dinge zeigten sich erst an echten Formelwerten:

- Der Schwellwert muss die **Steilheit** der Nullstelle prüfen, nicht die Höhe. Der Wert
  *an* einem Nulldurchgang ist definitionsgemäß fast null — eine Höhenschwelle bringt bei
  30 fps alles zum Schweigen.
- Monotone Zeit ist vorzeichenbehaftet und startet weit unter null, „noch nie ausgelöst"
  braucht also einen eigenen Fall statt einer sehr kleinen Zahl.

## M4 · `/studio` — Grundgerüst ✅

LiveView mit Transport, Stage (bestehenden Pixel-Canvas-Hook wiederverwenden,
quadratische Pixel), Pegelmeter je Panel, Slot-Liste (8), Probes-Liste,
Szenen-Referenz. Zunächst überwiegend anzeigen; bedienbar sind Transport und Slots.

**Fertig.** `/studio` (im Menü neben „Foyer") zeigt Transport, die Ring-Vorschau, je
Panel einen vorzeichenbehafteten Probe-Balken und einen Pegelmeter, die referenzierte
Szene und die Klangquellen, die es heute gibt: Metronom und Ring-Chase mit Klang,
Länge und Mindeststeilheit.

Gespielte Noten laufen dafür über ein eigenes PubSub-Thema — Noten sind selten genug
für eine Nachricht pro Stück, anders als Frames. Probe-Werte kommen mit jedem Frame und
werden auf zehn pro Sekunde gedrosselt.

## M5 · Grid und Kompositionen ✅

**Fertig.** Step-Grid mit **Panel je Schritt**, acht Slots, Playhead, A/B, Speichern,
Laden, Take. Nachgemessen im Browser: ein Muster aus Panel 1/3/3/3 und 7/7 spielt mit
Pegelmetern genau auf den Kanälen 1, 3 und 7, während der Playhead durch die Spalten
läuft — und nach einem kompletten Serverneustart kommt die gespeicherte Komposition
mit jedem Schritt und Panel zurück.

**Abweichung vom ursprünglichen Plan:** Kompositionen liegen in einer eigenen
Tabelle, nicht im App-Mode-Preset-System. Die Presets unter `priv/app_mode_presets`
werden zur *Compilezeit* eingelesen und lassen sich zur Laufzeit gar nicht schreiben —
eine Komposition entsteht aber beim Hören. Die Einreihung in die Rotation bleibt
davon unberührt und gehört ohnehin nach M7.

Nebenbei repariert: Das Metronom saß in derselben Quelle wie das Muster, ein Klick
auf „Metronom" hätte das Muster ersetzt. Es sitzt jetzt daneben.

## M6 · Matrix und Quellen

Modulationsmatrix mit Richtungsfilter, Quellen-Reiter (Probes · Features · LFOs ·
MIDI). Ab hier sind alle drei Kopplungsrichtungen bedienbar.

**Fertig, wenn:** die Zielbilder 2 (Voicing-Drone) und 5 (Onset-Blitz) ohne Code
gebaut werden können.

## M7 · Programm-Ebene

Freigabe-Flag, Kompositionen in der Warteschlange der bestehenden Konsole, Übergänge
mit Tonüberblendung auf der Taktgrenze, „Übernehmen".

**Fertig, wenn:** die Installation eine Nacht lang allein durch drei Kompositionen
rotiert und die Übergänge sitzen.

## M8 · SuperCollider (falls nicht schon in M0)

`Engine.SuperCollider` mit SynthDef-Set, Buffers, Timetag-Scheduling und
Feature-Rückkanal. Die Oberfläche ändert sich dabei nicht.

**Fertig, wenn:** der Timing-Modus im Transport „taktgenau" zeigt und Perkussion
hörbar präziser sitzt als mit beak.

---

## Ausprobieren (Stand M1)

Einmalig, nach dem Installieren von SuperCollider:

```bash
mix sound.synthdefs
```

Dann in `iex -S mix phx.server` (dev startet scsynth selbst, Stereo):

```elixir
Octopus.Sound.engine()                          # welches Backend, welches Timing
Octopus.Sound.note(channel: 1, synth: "pc_ping", note: 72)
Octopus.Sound.metronome(true)
Octopus.Sound.set_bpm(96)
Octopus.Sound.play()
Octopus.Sound.position()
Octopus.Sound.panic()
```

Eigene Ereignisquelle statt Metronom — so wird daraus in M3 der Ring-Chase:

```elixir
Octopus.Sound.set_source(fn step, _timeline ->
  if rem(step.index, 4) == 0 do
    [%{channel: rem(div(step.index, 4), 12) + 1, note: 72, synth: "pc_ping"}]
  else
    []
  end
end)
```

Der Ring-Chase (Zielbild 1), sobald eine Pixelfun-Szene läuft:

```elixir
Octopus.Sound.ring_chase(true)
Octopus.Sound.configure_ring_chase(synth: "pc_pluck", duration_ms: 900)
```

Er braucht **keinen** Transport — das Bild ist die Uhr. Wer ihn im Takt will, bindet die
Szene an Beats (`time_source: :beats`, M4).

Ein Muster aus dem Kopf:

```elixir
alias Octopus.Sound.Pattern
Octopus.Sound.update_pattern(&(&1 |> Pattern.put_step(1, 0, 1) |> Pattern.put_step(1, 4, 4)))
Octopus.Sound.play()
```

Alles davon geht seit M4 auch ohne IEx: **`/studio`** im Menü. Der Ring-Chase braucht
dort nur eine laufende Pixelfun-Szene und einen Klick.

Umschalten auf beak: in `config/dev.exs` `engine: Octopus.Sound.Engine.Beak`. Oben
ändert sich nichts, nur der Timing-Modus meldet dann `:immediate`.

**Auf einem Stereo-Laptop** faltet `mapping: :fold` (in `config/dev.exs` gesetzt) die
zwölf Panels auf die vorhandenen Ausgänge, sonst wären zehn davon stumm. Die
Installation läuft mit `:direct` — ein Ausgang pro Panel.

---

## Reihenfolge auf einen Blick

```
M0 Ton ✅ ► M1 Uhr ✅ ► M2 Probes ✅ ► M3 Ring-Chase ✅ ► M4 Studio ✅ ► M5 Grid ✅
                                          │                            │
                                    „hört man das Bild?" ✅     M6 Matrix ──► M7 Programm
                                                                             │
                                                                       M8 SuperCollider
```

M0–M3 sind klein und liefern das Erlebnis. Alles ab M4 ist Ausbau, der sich am
Gehörten orientieren kann.
