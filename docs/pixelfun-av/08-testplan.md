# 08 — Manueller Testplan

Für den Durchgang durch alles, was in M0–M6 entstanden ist. Gedacht zum
Abhaken: links der Schritt, rechts was passieren soll. Wo etwas anders ist,
notier es unten unter „Befunde" — dort steht auch, was ein guter Fehlerbericht
enthält.

**Bekannte Grenzen** stehen am Ende. Bitte vorher überfliegen, damit du nicht
Zeit mit Dingen verbringst, von denen wir schon wissen, dass sie noch fehlen.

## Vorbereitung

```bash
cd octopus
mix sound.synthdefs          # einmalig, braucht SuperCollider
BOOT_APP=PixelFun mix phx.server
```

Dann `http://localhost:4000/studio` öffnen.

> **Ton auf dem Laptop:** In dev sind zwei Ausgänge konfiguriert und die zwölf
> Panels werden darauf gefaltet (`mapping: :fold`). Du hörst die Bewegung
> also als Links/Rechts-Wechsel, nicht als Kreis. Das ist Absicht — sonst
> wären zehn von zwölf Panels stumm.

---

## A · Engine und Start

| # | Schritt | Erwartet |
|---|---|---|
| A1 | Studio öffnen | Transport zeigt Engine **SuperCollider**, Badge **taktgenau** (grün) |
| A2 | Serverlog ansehen | `scsynth is up, loading SynthDefs from …`, keine `FAILURE` |
| A3 | `Octopus.Sound.note(channel: 1)` in IEx | Ein Ton ist hörbar |
| A4 | Server mit Strg-C beenden, `pgrep scsynth` | Kein scsynth mehr übrig |
| A5 | scsynth von Hand starten, dann Server starten | Server übernimmt den laufenden Server, startet keinen zweiten, kein „address in use" |
| A6 | In `config/dev.exs` `engine: Octopus.Sound.Engine.Beak`, neu starten | Badge zeigt **best effort**, Töne kommen aus beak (sofern beak läuft) |
| A7 | `engine: Octopus.Sound.Engine.Null`, neu starten | Badge zeigt **kein Klang**, Seite funktioniert vollständig weiter |

## B · Transport

| # | Schritt | Erwartet |
|---|---|---|
| B1 | Play drücken | Position zählt hoch, Knopf wird zu Stop |
| B2 | Bei 120 BPM zehn Sekunden laufen lassen | Position ist um 20 Beats weitergelaufen (5 Takte) |
| B3 | Stop, 10 s warten, Play | Position steht während der Pause still und läuft dann weiter |
| B4 | Während des Laufens Tempo von 120 auf 60 ändern | Position springt **nicht**, läuft nur halb so schnell weiter |
| B5 | Tempo auf 240 | Doppelte Geschwindigkeit, wieder ohne Sprung |
| B6 | Panic drücken | Alles sofort still |
| B7 | Zweiten Browsertab auf `/studio` öffnen | Beide Tabs zeigen dieselbe Position, dasselbe Tempo, dasselbe Grid |

## C · Probes (die Brücke vom Bild zum Klang)

| # | Schritt | Erwartet |
|---|---|---|
| C1 | Studio bei laufender Pixelfun-Szene | Zwölf Balken bewegen sich, jeder wächst von der Mittellinie nach oben oder unten |
| C2 | Im Foyer die Formel auf `1` setzen | Alle zwölf Balken stehen gleich hoch, ganz oben |
| C3 | Formel auf `0-1` | Alle Balken ganz unten |
| C4 | Formel auf `sin(x*0.5 - t)` | Eine Welle wandert sichtbar durch die zwölf Balken |
| C5 | Pixelfun im Foyer beenden | Szenen-Karte sagt „Kein Pixel Fun aktiv", Balken stehen still |
| C6 | Pixelfun wieder starten | Balken laufen wieder, ohne Neuladen der Seite |

## D · Ring-Chase (Licht → Sound)

Voraussetzung: Pixelfun läuft mit `sin(x*0.5 - t)`.

| # | Schritt | Erwartet |
|---|---|---|
| D1 | Ring-Chase einschalten | Regelmäßige kurze Töne, die im Stereobild hin- und herwandern |
| D2 | Pegelmeter unter den Probe-Balken beobachten | Sie leuchten der Reihe nach auf, in Wanderrichtung |
| D3 | Formel auf `sin(x*0.5 + t)` ändern | Die Bewegung dreht sich um |
| D4 | Formel auf `sin(x*0.5 - t*3)` | Deutlich schneller **und** hörbar lauter (steilere Nulldurchgänge) |
| D5 | Formel auf `sin(x*0.5 - t*0.05)` | Sehr langsam; ab einem Punkt verstummt es (Mindeststeilheit) |
| D6 | Mindeststeilheit auf Minimum ziehen | Auch die langsame Welle klingt wieder |
| D7 | Klang auf `pc_pluck`, Länge auf 1500 ms | Gezupfter, lang ausklingender Klang statt kurzem Ping |
| D8 | Mindeststeilheit auf Maximum | Stille, bis die Welle wieder sehr steil wird |
| D9 | Ring-Chase ausschalten | Sofort still, keine Nachzügler |
| D10 | Transport auf Stop, Ring-Chase an | Klingt trotzdem — der Chase braucht keinen Transport, das Bild ist die Uhr |

## E · Drone (Licht → Sound, gehalten)

| # | Schritt | Erwartet |
|---|---|---|
| E1 | Drone einschalten | Ein Klangteppich setzt langsam ein (kein Knacken, kein Schlag) |
| E2 | Formel `1` | Alle Stimmen klingen, dichtester Akkord |
| E3 | Formel `0-1` | Der Drone verstummt, bleibt aber eingeschaltet |
| E4 | Formel `sin(x*0.5 - t*0.3)` | Der Akkord wandert hörbar, Stimmen kommen und gehen |
| E5 | Im Foyer den Zoom weit aufdrehen (feines Muster) | Mehr Stimmen gleichzeitig, flirrender |
| E6 | Zoom weit zurück (grobes Muster) | Wenige stehende Töne |
| E7 | Drone ausschalten | Ausklingen über ein paar Sekunden, kein abruptes Abschneiden |
| E8 | Drone an **und** Ring-Chase an | Beides gleichzeitig hörbar, kein Aussetzer |

## F · Grid (Partitur)

| # | Schritt | Erwartet |
|---|---|---|
| F1 | Panel-Pinsel auf 3, Zelle in Zeile 1 Schritt 1 klicken | Zelle wird blau und zeigt „3" |
| F2 | Dieselbe Zelle nochmal klicken | Zelle ist wieder leer |
| F3 | Zelle setzen, Pinsel auf 7, dieselbe Zelle klicken | Zelle zeigt „7" — verschoben, nicht gelöscht |
| F4 | Vier Schritte in Zeile 1 setzen, Play | Playhead wandert, an den gesetzten Schritten klingt es |
| F5 | Verschiedene Panels in einer Zeile | Der Klang wechselt hörbar die Seite (in dev: links/rechts) |
| F6 | Zeile 1 stummschalten (Zahl links) | Zeile wird rot, ist still, Schritte bleiben stehen |
| F7 | Stumm wieder aus | Klingt wieder wie vorher |
| F8 | Klang einer Zeile auf `pc_drone` | Diese Zeile klingt lang und weich |
| F9 | ⌫ in einer Zeile | Nur diese Zeile ist leer |
| F10 | Metronom an, während ein Muster läuft | Klick **zusätzlich** zum Muster; das Muster bleibt erhalten |
| F11 | Metronom aus | Muster läuft unverändert weiter |
| F12 | Tempo während des Spielens ändern | Muster wird schneller/langsamer, verliert den Takt nicht |

## G · Kompositionen

| # | Schritt | Erwartet |
|---|---|---|
| G1 | Muster bauen, Namen eingeben, Speichern | Meldung „gespeichert", Name erscheint rechts in der Liste |
| G2 | Ohne Namen speichern | Fehlermeldung, nichts wird gespeichert |
| G3 | Etwas ändern, unter **demselben** Namen speichern | Kein zweiter Eintrag, der bestehende wird überschrieben |
| G4 | Take drücken | Neuer Eintrag „Take JJJJ-MM-TT hh:mm:ss", Arbeitsversion unverändert |
| G5 | Grid leeren, gespeicherte Komposition laden | Muster ist vollständig zurück, inklusive Panel je Schritt |
| G6 | Beim Laden aufs Tempo achten | Tempo springt auf das gespeicherte |
| G7 | Server beenden und neu starten, Seite laden | Grid ist leer, Liste zeigt die Kompositionen; Laden stellt alles wieder her |
| G8 | Eintrag löschen (×) | Nachfrage, danach aus der Liste verschwunden |
| G9 | A/B: Muster in A, auf B umschalten | B ist leer, A bleibt erhalten |
| G10 | In B etwas anderes bauen, hin- und herschalten | Beide Muster bleiben unabhängig erhalten |
| G11 | „A→B kopieren", dann umschalten | B hat dasselbe Muster wie A |

## H · Matrix

| # | Schritt | Erwartet |
|---|---|---|
| H1 | Quelle „Klang · Onsets", Ziel „Szene · Sättigung", ＋ Zeile | Zeile erscheint, Richtung **Sound → Licht** |
| H2 | Ring-Chase an, Szenen-Karte beobachten | Sättigung springt bei jedem Ton hoch und fällt zurück |
| H3 | Betrag auf 0 ziehen | Sättigung bleibt still stehen |
| H4 | Betrag auf 1 | Deutlich größerer Ausschlag |
| H5 | Kurve auf `exp` | Nur kräftige Anschläge schlagen noch durch |
| H6 | Kurve auf `inverse` | Der Ausschlag kehrt sich um |
| H7 | Zeile mit ◼ deaktivieren | Parameter geht auf den Ausgangswert zurück |
| H8 | Zeile mit × entfernen | Parameter bleibt auf dem Ausgangswert |
| H9 | Quelle „Phase · 8 Takte" → „Szene · Zoom", Transport an | Das Bild atmet über acht Takte hinein und wieder heraus |
| H10 | Quelle „Probes · Maximum" → „Drone · Lautstärke" | Richtung **Licht → Sound**; der Drone schwillt mit dem Bild |
| H11 | Filter „Licht → Sound" | Nur diese Zeile bleibt sichtbar |
| H12 | Filter „Alle" | Alle Zeilen wieder da |
| H13 | Zwei Zeilen auf dasselbe Ziel | Beide Beträge addieren sich, nichts überschreibt das andere |
| H14 | Quellen-Karten unten beobachten | Vier Balken bewegen sich live mit Bild und Klang |
| H15 | Alles an (Chase, Drone, Grid, drei Matrixzeilen), fünf Minuten laufen lassen | Nichts hakt, keine Fehler im Log, Bild bleibt flüssig |

## I · Zusammenspiel und Robustheit

| # | Schritt | Erwartet |
|---|---|---|
| I1 | Während alles läuft: Browsertab schließen und neu öffnen | Ton läuft ununterbrochen weiter, Seite zeigt den echten Zustand |
| I2 | Netzwerk kurz trennen (LiveView-Reconnect) | Nach dem Reconnect stimmen Schalterstellungen und Grid |
| I3 | Zwei Tabs, in einem das Grid ändern | Der andere Tab folgt sofort |
| I4 | Panic bei laufendem Chase + Drone + Grid | Sofort still |
| I5 | Nach Panic: Drone aus- und wieder einschalten | Drone klingt wieder (siehe bekannte Grenzen) |
| I6 | Im Foyer die Szene wechseln | Probes, Chase und Drone folgen der neuen Szene |
| I7 | Pixelfun beenden, während Chase und Drone laufen | Keine Fehler, es wird still; nach dem Neustart läuft es weiter |
| I8 | CPU-Auslastung im Blick behalten | Frames bleiben bei 30 fps, keine Aussetzer im Ton |

---

## Befunde

Für jeden Fund bitte notieren:

1. **Nummer aus diesem Plan** (oder „neu"), und was du getan hast
2. **Erwartet / tatsächlich** in je einem Satz
3. **Szene** (Formel) und **Zustand** (was war an: Chase, Drone, Grid, Matrixzeilen)
4. **Reproduzierbar?** — immer, manchmal, einmalig
5. Auffälligkeiten im **Serverlog** (besonders Zeilen mit `[scsynth]`)

Der dritte Punkt ist der wichtigste: fast alles hier hängt an der Formel, und
derselbe Klick fühlt sich bei einer langsamen Welle völlig anders an als bei
einem flirrenden Muster.

---

## Bekannte Grenzen (kein Fehler)

- **Der Drone taucht in den Pegelmetern nicht auf.** Die Meter reagieren auf
  angeschlagene Noten; gehaltene Stimmen haben keinen Anschlag.
- **Nach Panic muss der Drone einmal aus- und wieder eingeschaltet werden.**
  Panic räumt im Klangserver alles ab, der Drone hält aber noch seine Stimmen
  für lebendig und redet ins Leere.
- **Die Matrix merkt sich den Ausgangswert beim Anlegen der Zeile.** Wenn du
  den Parameter danach im Foyer von Hand verstellst, springt er beim Entfernen
  der Zeile auf den *alten* Wert zurück.
- **Kompositionen speichern das Muster, nicht die Szene.** Die Formel wird nur
  zur Erinnerung mitgeschrieben; beim Laden wechselt das Bild nicht mit.
  Ebenso wenig gespeichert: Matrixzeilen, Chase- und Drone-Einstellungen.
- **A/B hält nur Muster**, keine Matrix und keine Instrumenteneinstellungen.
- **Kein Rotationsbetrieb.** Freigabe, Warteschlange und Übergänge zwischen
  Kompositionen sind M7 und noch nicht gebaut.
- **Die Szene wird nur angezeigt, nicht bearbeitet.** Formel und
  Szenenparameter ändert man weiter im Foyer.
- **In dev nur zwei Ausgänge.** Räumlichkeit über zwölf echte Kanäle lässt
  sich am Laptop nicht beurteilen (siehe
  [07-hardware-prototyp.md](07-hardware-prototyp.md)).
