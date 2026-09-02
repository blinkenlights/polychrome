# 09 — Was zwischen Entwurf und Studio noch fehlt

Bestandsaufnahme nach fünf Testrunden. Vergleich zwischen
[studio-entwurf.html](studio-entwurf.html) und der gebauten Seite `/studio`.

Zwei getrennte Fragen, die leicht durcheinandergehen:
**A · Aussehen und Aufteilung** (der Entwurf existiert, das Studio sieht anders aus)
und **B · Funktionen** (etwas gibt es überhaupt noch nicht).

---

## A · Aussehen und Aufteilung

### A1 · Der Streifen ist fast nur Lücke

**Befund:** Die Panels sind winzig und stehen weit auseinander.

**Ursache:** Der Streifen wird von der bestehenden Simulator-Ansicht gezeichnet,
und die zeigt die *echte* Geometrie der Installation: Panel 8 px breit,
`panel_gap` **18 px**. Über zwei Drittel der Breite sind also Lücke — auf dem
Ring stimmt das (die Panels stehen wirklich weit auseinander), in einer
abgewickelten Studioansicht will man das Bild sehen, nicht den Abstand.

**Lösung:** Das Streifen-Layout überschreibt den Abstand (1 px statt 18) und
bekommt eine größere Pixelgröße. Eine Zeile im Layout-Generator, eine im
Installations-Eintrag.

### A2 · Der Pegel klebt nicht am Panel

**Befund:** Im Entwurf sitzt unter jedem Panel direkt sein Pegelmeter; gebaut
ist ein separates Zwölferraster unter der ganzen Leinwand.

**Ursache:** Streifen und Meter sind zwei verschiedene Dinge — der Streifen ist
eine eingebettete LiveView mit eigener Leinwand und eigener Skalierung, die Meter
sind DOM-Elemente daneben. Sie können nicht aneinander ausgerichtet sein.

**Zwei Wege:**
1. **Abstand kollabieren (A1) und beides auf dasselbe 12-Spalten-Raster legen.**
   Billig, sieht fast richtig aus, bleibt aber eine Näherung.
2. **Den Streifen selbst zeichnen** — ein kleiner Canvas-Hook, der Frame,
   Pegel und Probe-Balken in einem Bild rendert. Mehr Arbeit, dafür pixelgenau
   und genau der Entwurf.

### A3 · Schrift und Farben

**Befund:** Der Entwurf ist eine dunkle Instrumentenkonsole in IBM Plex mit
Amber für Bild und Cyan für Klang. Gebaut ist die App-Oberfläche mit ihrem
daisyUI-Thema.

**Das ist eine Entscheidung, kein Versehen:** Soll `/studio` wie der Rest der
App aussehen — oder wie ein eigenes Gerät? Für den zweiten Weg genügt ein auf die
Seite begrenztes Thema (eigene CSS-Variablen plus Schriften), das nichts anderes
anfasst.

### A4 · Die linke Spalte fehlt ganz

**Im Entwurf:** Formelfeld, Variablenleiste, Szenen-Slots (A/B/C/+),
Wechselregel, Zeitquelle Sekunden ↔ Beats, dazu Zoom, Rotation, Sättigung,
Rot-Sweep als Regler.

**Gebaut:** nichts davon. Die Szene steht als schmale Karte rechts, nur lesbar,
mit Link ins Foyer.

**Hintergrund:** Wir hatten entschieden, dass die Szene **referenziert** wird
(Entscheidung 6 in [04](04-offene-fragen.md)) — sonst gäbe es zwei Editoren für
dieselbe Sache. Der Entwurf ist älter als diese Entscheidung.

**Vorschlag:** Mittelweg. Die Formel bleibt im Foyer. In die linke Spalte kommen
die Parameter, die man **beim Hören** dreht, weil sie direkt den Klang formen:
Zoom, Rotation, Sättigung, Pattern-Tempo — und die Zeitquelle. Alles andere
bleibt ein Link.

### A5 · Die Klangspalte ist etwas anderes geworden ✅ erledigt

> **Gebaut.** Die Spalte ist jetzt die Liste aller acht Slots mit Auslöser und
> eigenem Pegel, darunter das Detailfeld für den gewählten. Chase und Drone sind
> dabei zu Slots geworden — siehe [10-slot-modell.md](10-slot-modell.md). Im Grid
> behält ein Slot, den das Raster nicht spielt, seine Zeile und zeigt darin, was
> ihn auslöst, statt sechzehn Zellen, die er nie benutzt.
>
> Offen bleibt daraus: **Slot-Typen Sample und Granular** (B2) und die
> **Ortsregeln im UI** — `:fixed` und `:rotate` gibt es im Modell, aber noch
> nicht zum Einstellen.

#### Ursprünglicher Befund

**Im Entwurf:** acht nummerierte Slots mit Typ (SYNTH / SAMPLE / GRANULAR /
LEER), Pegel je Slot, ausgewählter Slot hervorgehoben, darunter ein Detailfeld
für den gewählten Slot (SynthDef, Tonhöhe, Filter, Release, Kanal-Zuordnung).

**Gebaut:** drei Schalter (Metronom, Drone, Ring-Chase) plus Chase-Einstellungen.
Die acht Slots existieren zwar — aber als **Zeilen im Grid**, mit Name, Klang und
Mute inline.

**Das ist der größte strukturelle Unterschied.** Im Entwurf sind Slots
Instrumente, die man auswählt und einstellt; gebaut sind sie Zeilen eines
Rasters. Zusammenführen heißt: die Klangspalte wird die Slot-Liste plus Detail,
das Grid zeigt nur noch die Schritte.

### A6 · Kleinkram im Vergleich

| | Entwurf | Gebaut |
|---|---|---|
| Transport | Tap, Loop-Länge, AV-Offset, Master | fehlen alle vier |
| Bibliothek | „Für Rotation freigegeben", Performance-Modus | fehlen (M7) |
| Kopplungszone | drei **Reiter** Grid / Matrix / Quellen | zwei gestapelte Karten |
| Stage | „Was gerade koppelt" als Lesehilfe neben der Ringdraufsicht | fehlt |
| Ringdraufsicht | unter dem Streifen, neben der Lesehilfe | rechts neben dem Streifen |

---

## B · Funktionen, die es noch gar nicht gibt

Nach Nutzen sortiert, nicht nach Aufwand.

1. **Zeitquelle Sekunden ↔ Beats.** Der Grund, warum BPM den Ring-Chase nicht
   beeinflusst: die Szene läuft nach Sekunden, der Transport nach Takten. Erst
   die Umschaltung macht aus „Bild und Ton laufen nebeneinander" ein
   gemeinsames Stück. Steht im Konzept als Zielbild 4.
2. **Slot-Typen Sample und Granular.** Heute kann das Grid nur die vier
   SynthDefs auslösen. Für Samples fehlt in der SuperCollider-Engine die
   Buffer-Verwaltung (`/b_allocRead`).
3. **Kanal-Zuordnung je Slot** — „folgt Probe", „festes Panel", „alle Panels",
   „rotiert um n je Trigger". Heute steckt der Ort ausschließlich im Schritt.
4. **Master-Gain und Limiter.** Es gibt keinen Master. Für eine Installation,
   die stundenlang allein läuft, ist das die wichtigste fehlende Sicherung.
5. **AV-Offset.** Eingemessen wird bisher nichts; der Chase klingt konstant
   80 ms nach dem Bild.
6. **Tap-Tempo und Loop-Länge** im Transport.
7. **Kompositionen speichern nur das Muster.** ✅ *Teilweise erledigt:* Chase und
   Drone sind jetzt Slots und werden mitgespeichert — nach einem Serverneustart
   kommen sie klingend zurück. Offen bleiben **Matrixzeilen** und der
   **Szenenbezug**.
8. **Probes einstellen** — Position, Glättung, Schwelle, Ausgabeart. Die
   Quellen-Karten sind heute nur Anzeige.
9. **Der Drone fehlt in den Pegelmetern über dem Streifen**, weil die auf
   Anschläge reagieren und gehaltene Stimmen keinen haben. In der Klangspalte hat
   inzwischen jeder Slot seinen eigenen Pegel.
10. **M7 komplett** — Freigabe, Warteschlange, Übergänge auf der Taktgrenze.
11. **Performance-Modus.**

---

## Vorschlag für die Reihenfolge

**Stufe 1 — Stage reparieren (klein, größter sichtbarer Gewinn).**
A1 Abstand kollabieren, A2 Weg 1 (gemeinsames Raster), A6 Reiter für die
Kopplungszone, „Was gerade koppelt" ergänzen. Danach sieht die Mitte aus wie
gedacht.

**Stufe 2 — Aussehen.** A3, sobald entschieden ist, ob eigenes Gerät oder
App-Look.

**Stufe 3 — Spalten.** A4 linke Spalte (mit der Mittelweg-Entscheidung) und
A5 Klangspalte als Slot-Liste. Das ist der eigentliche Umbau.

**Stufe 4 — Funktion.** B1 Zeitquelle zuerst (macht aus zwei Sachen eine),
dann B4 Master, B5 AV-Offset, B7 vollständige Kompositionen, danach B2/B3.

**Offen bleibt bewusst:** M7 und der Performance-Modus.
