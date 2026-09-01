# 06 — Fahrplan

Reihenfolge nach einem Prinzip: **Das entscheidende Erlebnis zuerst, die schöne
Oberfläche danach.** Die ersten drei Schritte haben kein UI und liefern trotzdem den
Moment, an dem das Projekt real wird. Andersherum baut man zwei Wochen an einer
Oberfläche und merkt dann, dass sich die Kopplung anders anfühlt als gedacht.

## M0 · Ton aus dem Server

`Octopus.Sound`-Supervisor, das `Sound.Engine`-Behaviour und ein erstes Backend.
Bedienbar aus IEx, sonst nichts.

- `Sound.Engine` (Behaviour), `Sound.Engine.Beak` bzw. `Sound.Engine.SuperCollider`
- `Sound.panic/0`

**Fertig, wenn:** aus IEx ein Ton auf einem wählbaren Kanal erklingt und Panic ihn
sofort beendet.

> Welches Backend zuerst, ist eine reine Praxisfrage: Auf dem Zielrechner ist beak
> gesetzt (läuft schon). Auf einem Mac zum Entwickeln ist SuperCollider vermutlich
> schneller startklar (`brew install --cask supercollider`), während beak erst gebaut
> werden muss — das CMake-Setup ist auf Apple vorbereitet, aber ungetestet. Das
> Behaviour macht daraus eine Konfigurationszeile, keine Weggabelung.

## M1 · Die Uhr

`Sound.Clock` (BPM, Play/Stop, Position, PubSub-Broadcast der Beat-Phase) und
`Sound.Scheduler` mit Look-ahead-Fenster.

**Fertig, wenn:** ein Metronom über Minuten stabil läuft, ohne zu driften, und
`mix test` die Uhr-Mathematik prüft (Takt/Beat/Step aus monotoner Zeit, Loop-Umbruch,
Tempowechsel).

## M2 · Probes in Pixelfun

Kleiner, klar abgegrenzter Eingriff in `pixel_fun.ex`: hinter einem Schalter pro Frame
zusätzlich N Punkte auswerten und als `{:pixel_probes, %{t_beats: _, values: [...]}}`
broadcasten.

**Fertig, wenn:** ein IEx-Listener die zwölf Werte im Takt der Frames sieht und die
Renderleistung messbar unverändert ist.

## M3 · Ring-Chase — das erste audiovisuelle Ergebnis

Der Scheduler verbindet Probes mit Tönen: Nulldurchgang an Panel n → kurzer Ton auf
Kanal n. Formel und Klang zunächst fest verdrahtet.

**Fertig, wenn:** man das Bild wandern *hört*. Ab hier ist das Projekt real, und alle
weiteren Entscheidungen lassen sich am Höreindruck treffen statt am Papier.

## M4 · `/studio` — Grundgerüst

LiveView mit Transport, Stage (bestehenden Pixel-Canvas-Hook wiederverwenden,
quadratische Pixel), Pegelmeter je Panel, Slot-Liste (8), Probes-Liste,
Szenen-Referenz. Zunächst überwiegend anzeigen; bedienbar sind Transport und Slots.

**Fertig, wenn:** man M3 ohne IEx starten, hören und beobachten kann.

## M5 · Grid und Kompositionen

Step-Grid inkl. Panel je Step. `Composition` als Ecto-Schema, gespeichert im
vorhandenen App-Mode-Preset-System. Speichern/Laden, A/B, Take.

**Fertig, wenn:** eine gebaute Komposition einen Neustart überlebt und sich per
Auswahl zurückholen lässt.

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

## Reihenfolge auf einen Blick

```
M0 Ton ──► M1 Uhr ──► M2 Probes ──► M3 Ring-Chase ──► M4 Studio ──► M5 Grid
                                          │                            │
                                    „hört man das Bild?"        M6 Matrix ──► M7 Programm
                                                                             │
                                                                       M8 SuperCollider
```

M0–M3 sind klein und liefern das Erlebnis. Alles ab M4 ist Ausbau, der sich am
Gehörten orientieren kann.
