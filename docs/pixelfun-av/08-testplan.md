# 08 — Manueller Testplan

Stand nach dem ersten Durchgang. Legende:

| | |
|---|---|
| ✅ | bestanden, nichts zu tun |
| 🔁 | **nachtesten** — der Fall ist seither repariert oder der Testfall war falsch |
| ⬜ | noch offen |

**Offen sind 22 Fälle**, davon 13 zum Nachtesten. Der ganze Block I (Zusammenspiel)
ist noch unberührt.

## Was sich seit dem ersten Durchgang geändert hat

- **Der Chase stolpert nicht mehr.** Zwei Ursachen: die Formel `sin(x*0.5 - t)`
  läuft nicht sauber um den Ring (Naht zwischen Panel 12 und 1), und der
  Zeitstempel der Probes hing an der Renderdauer statt am Frame-Raster.
  Nachgemessen über 270 Frames: Abstände vorher 503–540 ms, jetzt 518–519 ms.
- **Neue Formelempfehlung** für alles auf dem Ring: `sin(atan2(ny,nx) - t)`.
- **Der Drone ist zwölfstimmig** — er zählte vorher Ausgangskanäle statt Panels.
- **Panel 1 und 7 liegen nicht mehr auf demselben Lautsprecher.**
- **Panic stoppt jetzt auch Transport und Instrumente.**
- **Neu in der Stage:** abgewickelter Streifen und Ringdraufsicht.
- **Dropdowns zeigen wieder ihren Text.**

## Vorbereitung

```bash
cd octopus
mix sound.synthdefs          # einmalig, braucht SuperCollider
BOOT_APP=PixelFun mix phx.server
```

Dann `http://localhost:4000/studio` öffnen.

> **Ton auf dem Laptop:** zwei Ausgänge, der Ring wird in zusammenhängende Bögen
> gefaltet — Panel 1–6 links, 7–12 rechts. Bewegung um den Ring hörst du also als
> Wechsel zwischen links und rechts.

---

## A · Engine und Start

| # | | Schritt | Erwartet |
|---|---|---|---|
| A1 | ✅ | Studio öffnen | Engine **SuperCollider**, Badge **taktgenau** |
| A2 | ✅ | Serverlog | `loading SynthDefs from …`, keine `FAILURE` |
| A3 | ✅ | `Octopus.Sound.note(channel: 1)` in IEx | Ein Ton |
| A4 | ⬜ | Server mit Strg-C beenden, `pgrep scsynth` | Kein scsynth mehr übrig |
| A5 | ⬜ | scsynth von Hand starten, dann Server starten | Server übernimmt ihn, kein „address in use" |
| A6 | ⬜ | `engine: Octopus.Sound.Engine.Beak` in `config/dev.exs`, neu starten | Badge **best effort** |
| A7 | ⬜ | `engine: Octopus.Sound.Engine.Null`, neu starten | Badge **kein Klang**, Seite funktioniert vollständig |
| A8 | 🔁 | Stage ansehen | Links der **abgewickelte Streifen** (12 Panels nebeneinander), rechts die **Ringdraufsicht** |
| A9 | 🔁 | Dropdowns im Klang-Bereich und über dem Streifen | Der gewählte Eintrag ist lesbar, nicht abgeschnitten |

## B · Transport

| # | | Schritt | Erwartet |
|---|---|---|---|
| B1 | ✅ | Play | Position zählt hoch |
| B2 | ✅ | Zehn Sekunden bei 120 BPM | 20 Beats weiter (5 Takte) |
| B3 | ✅ | Stop, warten, Play | Steht still, läuft dann weiter |
| B4 | ✅ | Tempo 120 → 60 im Lauf | Kein Sprung, halbes Tempo |
| B5 | ✅ | Tempo → 240 | Doppeltes Tempo, kein Sprung |
| B6 | 🔁 | **Erst** Ring-Chase oder Grid starten, dann Panic | Ton sofort still, **Transport stoppt**, Ring-Chase und Drone gehen aus. Die Animation läuft weiter — Panic ist der Not-Aus für den Ton |
| B7 | ✅ | Zweiter Browsertab | Beide zeigen denselben Zustand |

## C · Probes

| # | | Schritt | Erwartet |
|---|---|---|---|
| C1 | ✅ | Studio bei laufender Szene | Zwölf Balken bewegen sich um die Mittellinie |
| C2 | ✅ | Formel `1` | Alle Balken gleich hoch, ganz oben |
| C3 | ✅ | Formel `0-1` | Alle ganz unten |
| C4 | ✅ | Formel `sin(x*0.5 - t)` | Eine Welle wandert durch die Balken |
| C5 | 🔁 | Pixelfun im Foyer **beenden** (nicht nur wegschalten) | „Kein Pixel Fun aktiv", Balken stehen still. Nur weggeschaltet läuft die App weiter — das ist so gewollt |
| C6 | ⬜ | Pixelfun wieder starten | Balken laufen wieder, ohne Neuladen |

## D · Ring-Chase (Licht → Sound)

**Voraussetzung: Formel `sin(atan2(ny,nx) - t)`.**

Nicht `sin(x*0.5 - t)`. Nachgemessen: dort sitzen elf Abstände bei 0,433 s und
einer — zwischen Panel 12 und 1 — bei 1,5 s. `x*k` läuft nur rund, wenn `k` mal
die Ringbreite ein Vielfaches von 2π ergibt. `atan2(ny,nx)` ist der Azimut selbst
und läuft immer rund; der Faktor davor ist die Anzahl Wellen auf dem Ring.

| # | | Schritt | Erwartet |
|---|---|---|---|
| D1 | 🔁 | Ring-Chase an | **Gleichmäßige** Töne, kein Stolpern, **keine Lücke** zwischen Panel 12 und 1 |
| D2 | 🔁 | Pegelmeter beobachten | Leuchten der Reihe nach in Wanderrichtung |
| D3 | 🔁 | Formel `sin(atan2(ny,nx) + t)` | Bewegung dreht sich um |
| D4 | 🔁 | Formel `sin(atan2(ny,nx) - t*3)` | Schneller und lauter, **weiterhin gleichmäßig** |
| D5 | 🔁 | Formel `sin(atan2(ny,nx) - t*0.05)` | Sehr langsam; ab einem Punkt verstummt es |
| D6 | 🔁 | Mindeststeilheit aufs Minimum (0.0005) | Auch die langsame Welle klingt wieder |
| D7 | ⬜ | Klang `pc_pluck`, Länge 1500 ms | Gezupft, lang ausklingend |
| D8 | ⬜ | Mindeststeilheit aufs Maximum | Stille, bis die Welle sehr steil wird |
| D9 | ⬜ | Ring-Chase aus | Sofort still, keine Nachzügler |
| D10 | ⬜ | Transport auf Stop, Chase an | Klingt trotzdem — das Bild ist die Uhr |
| D11 | 🔁 | Formel `sin(atan2(ny,nx)*3 - t)` | **Drei Töne exakt gleichzeitig**, dann die nächsten drei — kein Versatz innerhalb einer Gruppe |

## E · Drone

| # | | Schritt | Erwartet |
|---|---|---|---|
| E1 | ✅ | Drone an | Klangteppich setzt langsam ein |
| E2 | ✅ | Formel `1` | Alle Stimmen klingen |
| E3 | ✅ | Formel `0-1` | Verstummt, bleibt aber an |
| E4 | 🔁 | Formel `sin(atan2(ny,nx) - t*0.3)` | Der Akkord wandert, Stimmen kommen und gehen — **deutlich mehrstimmig** |
| E5 | 🔁 | Zoom weit auf (feines Muster) | Mehr Stimmen gleichzeitig, flirrend |
| E6 | 🔁 | Zoom weit zurück | Wenige stehende Töne |
| E7 | ✅ | Drone aus | Ausklingen, kein Abschneiden |
| E8 | ✅ | Drone **und** Chase | Beides gleichzeitig, kein Aussetzer |

## F · Grid

| # | | Schritt | Erwartet |
|---|---|---|---|
| F1 | ✅ | Pinsel 3, Zelle klicken | Zelle blau mit „3" |
| F2 | ✅ | Nochmal klicken | Leer |
| F3 | ✅ | Pinsel 7, dieselbe Zelle | Zeigt „7" — verschoben, nicht gelöscht |
| F4 | ✅ | Vier Schritte, Play | Playhead wandert, es klingt an den Schritten |
| F5 | 🔁 | Panel 1 und Panel 7 in einer Zeile | Klang wechselt hörbar die Seite (1–6 links, 7–12 rechts) |
| F6–F12 | ✅ | Mute, Klang je Zeile, ⌫, Metronom, Tempo | wie beschrieben |

## G · Kompositionen

| # | | Schritt | Erwartet |
|---|---|---|---|
| G1–G10 | ✅ | Speichern, Take, Laden, Löschen, Neustart, A/B | wie beschrieben |
| G11 | 🔁 | Auf A stehen, „A → B kopieren", umschalten | B hat A's Muster. Der Knopf beschriftet sich um: auf B heißt er „B → A kopieren" und kopiert entsprechend |

## H · Matrix

| # | | Schritt | Erwartet |
|---|---|---|---|
| H1–H14 | ✅ | Zeile anlegen, Betrag, Kurve, Filter, zwei Zeilen auf ein Ziel | wie beschrieben |
| H15 | ⬜ | Alles an (Chase, Drone, Grid, drei Matrixzeilen), fünf Minuten | Nichts hakt, keine Fehler im Log, Bild bleibt flüssig |

## I · Zusammenspiel und Robustheit

| # | | Schritt | Erwartet |
|---|---|---|---|
| I1 | ⬜ | Tab schließen und neu öffnen | Ton läuft durch, Seite zeigt den echten Zustand |
| I2 | ⬜ | Netzwerk kurz trennen | Nach dem Reconnect stimmen Schalter und Grid |
| I3 | ⬜ | Zwei Tabs, in einem das Grid ändern | Der andere folgt sofort |
| I4 | ⬜ | Panic bei Chase + Drone + Grid | Sofort still, Transport aus, Instrumente aus |
| I5 | ⬜ | Nach Panic alles wieder einschalten | Klingt wieder |
| I6 | ⬜ | Szene im Foyer wechseln | Probes, Chase und Drone folgen der neuen Szene |
| I7 | ⬜ | Pixelfun beenden, während Chase und Drone laufen | Keine Fehler, es wird still; nach Neustart läuft es weiter |
| I8 | ⬜ | CPU im Blick | 30 fps, keine Aussetzer im Ton |

---

## Befunde

Für jeden Fund:

1. **Nummer** (oder „neu") und was du getan hast
2. **Erwartet / tatsächlich** in je einem Satz
3. **Szene** (Formel) und **Zustand** (was war an)
4. **Reproduzierbar?** — immer, manchmal, einmalig
5. Auffälligkeiten im **Serverlog** (besonders `[scsynth]`)

Punkt 3 ist der wichtigste: fast alles hängt an der Formel.

---

## Bekannte Grenzen (kein Fehler)

- **Der Drone taucht in den Pegelmetern nicht auf.** Die Meter reagieren auf
  angeschlagene Noten; gehaltene Stimmen haben keinen Anschlag.
- **Der Ring-Chase klingt 80 ms nach dem Bild.** Preis für gleichmäßiges Timing:
  der Nulldurchgang wird interpoliert und die Note konstant nach vorn geplant.
  Konstant statt zappelig — und genau dafür ist später der AV-Offset da.
- **In dev hörst du den Ring auf zwei Ausgängen** (1–6 links, 7–12 rechts).
- **Die Matrix merkt sich den Ausgangswert beim Anlegen der Zeile.** Verstellst
  du den Parameter danach im Foyer, springt er beim Entfernen auf den alten Wert.
- **Kompositionen speichern das Muster, nicht die Szene.** Matrixzeilen, Chase-
  und Drone-Einstellungen ebenfalls nicht.
- **A/B hält nur Muster.**
- **Kein Rotationsbetrieb** (Freigabe, Warteschlange, Übergänge) — das ist M7.
- **Die Szene wird nur angezeigt, nicht bearbeitet.**
