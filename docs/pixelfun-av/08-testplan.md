# 08 — Manueller Testplan

Stand nach dem ersten Durchgang. Legende:

| | |
|---|---|
| ✅ | bestanden, nichts zu tun |
| 🔁 | **nachtesten** — der Fall ist seither repariert oder der Testfall war falsch |
| ⬜ | noch offen |

> **Vor dem nächsten Durchgang: Server neu starten**, und im Foyer die
> **Rotation der Szene abschalten** (Rotation, Orbit, Sweeps) — siehe D-Block.

**Offen sind 8 Fälle**, davon 4 zum Nachtesten.

## Was sich seit dem vierten Durchgang geändert hat

- **Der Klang folgt jetzt der Wand.** Vorher schickte *jedes* laufende Pixel Fun
  Probes — und „Stop" im Foyer beendet die Übernahme, nicht die App. Also klang
  eine Szene weiter, die längst ersetzt war. Jetzt sendet Pixel Fun nur, solange
  es das Bild auf der Wand ist, und die Szenenkarte zeigt die Szene auf der Wand
  statt irgendeine laufende. Nachgeprüft: Fire auf die Wand holen → alle
  Pegelmeter auf null.
- **Die Länge des Chase-Klangs stand als „1.5e3 ms" da.**

## Was sich seit dem dritten Durchgang geändert hat

- **Das „Tempo wackelt nach einer Weile" ist die Szene, nicht die Uhr.**
  Im laufenden System über 75 s gemessen: Frames halten die Echtzeit auf eine
  Millisekunde, geplante Noten 518,4 ms ±0,6 in beiden Hälften, scsynth meldet
  nichts als verspätet. Sway und konstanter Orbit sind genauso gleichmäßig.
  Rotation nicht:

  | Szene | max. Abweichung |
  |---|---|
  | ohne Rotation | **0,6 ms** |
  | `rot_auto` (Sweep) | **254,8 ms** |
  | `roll_rate: 20` | **709,8 ms** |

  Das ist richtig so — Rotation dreht den Ring unter der Formel, die Welle
  läuft schneller und langsamer an den Panels vorbei, und der Chase folgt dem
  Bild. Es sieht nur aus wie ein Timing-Fehler. **Das Studio schreibt jetzt neben
  den Ring-Chase, welche Bewegung aktiv ist und was sie anrichtet.**
- **D11** litt zusätzlich an derselben Ursache: mit Rotation verschiebt sich die
  Gleichzeitigkeit der drei Töne zyklisch — „versetzt, dann unisono, dann wieder
  versetzt".

## Was sich seit dem zweiten Durchgang geändert hat

- **Der Chase-Zeitstempel hing an der Renderdauer.** Nachgemessen im laufenden
  System: Frames jetzt exakt 33,0 ms auseinander (Abweichung 0,0 ms), Noten
  518–519 ms (Abweichung 0,6 ms), Panels sauber 1…12 ohne Naht. Das war die
  Restursache von D1/D3/D4.
- **Jedes Panel hat jetzt eine eigene Tonhöhe.** Bei zwölf Panels und acht
  Skalentönen lagen Panel 1 und 9 auf demselben Ton — zwei gleiche gleichzeitige
  Töne interferieren, und das klingt wie Versatz. Das war D11.
- **C5 und E5/E6 waren falsche Testfälle von mir**, siehe dort.
- **G11 stimmt**, war ebenfalls ein alter Build.

## Was sich im ersten Durchgang geändert hatte

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
| A8 | ✅ | Stage ansehen | Links der **abgewickelte Streifen** (12 Panels nebeneinander), rechts die **Ringdraufsicht** |
| A9 | ✅ | Dropdowns im Klang-Bereich und über dem Streifen | Der gewählte Eintrag ist lesbar, nicht abgeschnitten |

## B · Transport

| # | | Schritt | Erwartet |
|---|---|---|---|
| B1 | ✅ | Play | Position zählt hoch |
| B2 | ✅ | Zehn Sekunden bei 120 BPM | 20 Beats weiter (5 Takte) |
| B3 | ✅ | Stop, warten, Play | Steht still, läuft dann weiter |
| B4 | ✅ | Tempo 120 → 60 im Lauf | Kein Sprung, halbes Tempo |
| B5 | ✅ | Tempo → 240 | Doppeltes Tempo, kein Sprung |
| B6 | ✅ | **Erst** Ring-Chase oder Grid starten, dann Panic | Ton sofort still, **Transport stoppt**, Ring-Chase und Drone gehen aus. Die Animation läuft weiter — Panic ist der Not-Aus für den Ton |
| B7 | ✅ | Zweiter Browsertab | Beide zeigen denselben Zustand |

## C · Probes

| # | | Schritt | Erwartet |
|---|---|---|---|
| C1 | ✅ | Studio bei laufender Szene | Zwölf Balken bewegen sich um die Mittellinie |
| C2 | ✅ | Formel `1` | Alle Balken gleich hoch, ganz oben |
| C3 | ✅ | Formel `0-1` | Alle ganz unten |
| C4 | ✅ | Formel `sin(x*0.5 - t)` | Eine Welle wandert durch die Balken |
| C5 | 🔁 | „Stop" im Foyer bei Pixelfun | Solange danach kein anderes Bild auf der Wand ist, läuft Pixel Fun weiter — „Stop" beendet die *Übernahme*, nicht die App. Sobald etwas anderes auf der Wand ist, sagt die Szenenkarte „Auf der Wand läuft gerade kein Pixel Fun" und der Klang verstummt |
| C6 | 🔁 | Anderes Pixelfun-Preset per Übernahme starten | Probes und Klang folgen sofort dem neuen Preset; das alte klingt **nicht** weiter |
| C7 | 🔁 | Eine Nicht-Pixelfun-App auf die Wand holen (z. B. Fire) | Szenenkarte: „Auf der Wand läuft gerade kein Pixel Fun", alle Pegelmeter auf null |

## D · Ring-Chase (Licht → Sound)

**Voraussetzung: Formel `sin(atan2(ny,nx) - t)` — und eine Szene ohne
Eigenbewegung.** Rotation, Orbit und die Auto-Sweeps drehen den Ring unter der
Formel; der Chase folgt und wird dadurch ungleichmäßig. Das Studio warnt neben
dem Ring-Chase, wenn etwas davon aktiv ist. Zum Testen im Foyer abschalten.

Nicht `sin(x*0.5 - t)`. Nachgemessen: dort sitzen elf Abstände bei 0,433 s und
einer — zwischen Panel 12 und 1 — bei 1,5 s. `x*k` läuft nur rund, wenn `k` mal
die Ringbreite ein Vielfaches von 2π ergibt. `atan2(ny,nx)` ist der Azimut selbst
und läuft immer rund; der Faktor davor ist die Anzahl Wellen auf dem Ring.

| # | | Schritt | Erwartet |
|---|---|---|---|
| D1 | ✅ | Ring-Chase an, Szenenbewegung aus | **Gleichmäßige** Töne, kein Stolpern, **keine Lücke** zwischen Panel 12 und 1 |
| D2 | ✅ | Pegelmeter beobachten | Leuchten der Reihe nach in Wanderrichtung |
| D3 | ✅ | Formel `sin(atan2(ny,nx) + t)` | Bewegung dreht sich um, gleichmäßig |
| D4 | ✅ | Formel `sin(atan2(ny,nx) - t*3)` | Schneller und lauter, weiterhin gleichmäßig |
| D5 | ✅ | Formel `sin(atan2(ny,nx) - t*0.05)` | **Stille ist das erwartete Ergebnis.** So eine Welle steigt nur um 0,0017 pro Frame und liegt damit unter der voreingestellten Mindeststeilheit von 0,002 — der Chase soll ein kaum bewegtes Bild nicht antasten. Weiter bei D6 |
| D6 | 🔁 | Mindeststeilheit aufs Minimum (0.0005) | Die langsame Welle klingt wieder — aber **sehr** sparsam: `t*0.05` braucht 125 s für eine Runde, das ist ein Ton alle ~10 s. Mindestens 30 s hinhören |
| D7 | 🔁 | Klang `pc_pluck`, Länge einmal auf **100 ms**, dann auf **2000 ms** | Deutlich unterschiedlich langer Ausklang. Nachgeprüft, dass der Regler ankommt; bei 400 ↔ 1500 ms ist der Unterschied auf einem Zupfklang subtiler als erwartet |
| D8 | ⬜ | Mindeststeilheit aufs Maximum | Stille, bis die Welle sehr steil wird |
| D9 | ✅ | Ring-Chase aus | Sofort still, keine Nachzügler |
| D10 | ✅ | Transport auf Stop, Chase an | Klingt trotzdem — das Bild ist die Uhr |
| D12 | ✅ | BPM ändern, während der Chase läuft | **Das Tempo ändert sich nicht, und das ist so.** Der Chase hängt am Bild, nicht am Transport; BPM steuert Grid und Metronom. Die Szene an den Takt zu binden ist gebaut, aber noch nicht bedienbar — siehe „fehlende Funktionen" |
| D11 | 🔁 | Formel `sin(atan2(ny,nx)*3 - t)`, **Szenenbewegung aus** | **Drei Töne exakt gleichzeitig**, dann die nächsten drei — und drei *verschiedene* Tonhöhen, kein Schweben |

## E · Drone

| # | | Schritt | Erwartet |
|---|---|---|---|
| E1 | ✅ | Drone an | Klangteppich setzt langsam ein |
| E2 | ✅ | Formel `1` | Alle Stimmen klingen |
| E3 | ✅ | Formel `0-1` | Verstummt, bleibt aber an |
| E4 | ✅ | Formel `sin(atan2(ny,nx) - t*0.3)` | Der Akkord wandert, Stimmen kommen und gehen — deutlich mehrstimmig |
| E5 | 🔁 | **Formel `sin(x*0.5 - t*0.3)`**, Zoom auf **×6** | Zoom **hoch = feineres Muster**: viele Stimmen wechseln schnell, flirrend. Mit `atan2` ist der Effekt absichtlich kaum hörbar — Richtungsformeln sind gegen Zoom weitgehend immun (siehe [pixelfun.md](../pixelfun.md)), dafür ist `x` da |
| E6 | 🔁 | Weiter mit `sin(x*0.5 - t*0.3)`, Zoom auf **×1** | Zoom **niedrig = gröberes Muster**: nur zwei, drei Töne stehen gleichzeitig |
| E7 | ✅ | Drone aus | Ausklingen, kein Abschneiden |
| E8 | ✅ | Drone **und** Chase | Beides gleichzeitig, kein Aussetzer |

## F · Grid

| # | | Schritt | Erwartet |
|---|---|---|---|
| F1 | ✅ | Pinsel 3, Zelle klicken | Zelle blau mit „3" |
| F2 | ✅ | Nochmal klicken | Leer |
| F3 | ✅ | Pinsel 7, dieselbe Zelle | Zeigt „7" — verschoben, nicht gelöscht |
| F4 | ✅ | Vier Schritte, Play | Playhead wandert, es klingt an den Schritten |
| F5 | ✅ | Panel 1 und Panel 7 in einer Zeile | Klang wechselt hörbar die Seite (1–6 links, 7–12 rechts) |
| F6–F12 | ✅ | Mute, Klang je Zeile, ⌫, Metronom, Tempo | wie beschrieben |

## G · Kompositionen

| # | | Schritt | Erwartet |
|---|---|---|---|
| G1–G10 | ✅ | Speichern, Take, Laden, Löschen, Neustart, A/B | wie beschrieben |
| G11 | 🔁 | Auf A stehen, „A → B kopieren", umschalten | B hat A's Muster. Nachgeprüft im Browser: auf A heißt der Knopf „A → B kopieren", auf B „B → A kopieren" — er kopiert immer die *laufende* Seite auf die andere. Danach haben beide Seiten dasselbe; das ist der Sinn der Sache |

## H · Matrix

| # | | Schritt | Erwartet |
|---|---|---|---|
| H1–H14 | ✅ | Zeile anlegen, Betrag, Kurve, Filter, zwei Zeilen auf ein Ziel | wie beschrieben |
| H15 | ⬜ | Alles an (Chase, Drone, Grid, drei Matrixzeilen), fünf Minuten | Nichts hakt, keine Fehler im Log, Bild bleibt flüssig |

## I · Zusammenspiel und Robustheit

| # | | Schritt | Erwartet |
|---|---|---|---|
| I1 | ⬜ | Tab schließen und neu öffnen | Ton läuft durch, Seite zeigt den echten Zustand |
| I3 | ⬜ | Zwei Tabs, in einem das Grid ändern | Der andere folgt sofort |
| I4 | ✅ | Panic bei Chase + Drone + Grid | Sofort still, Transport aus, Instrumente aus |
| I6 | 🔁 | Szene im Foyer wechseln | Probes, Chase und Drone folgen der neuen Szene |
| I7 | 🔁 | Pixelfun von der Wand nehmen, während Chase und Drone laufen | Es wird still, keine Fehler; kommt das Bild zurück, klingt es wieder |

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
