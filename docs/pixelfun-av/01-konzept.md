# 01 — Konzept

> Begriffe, die hier vorausgesetzt werden, stehen im [Glossar](00-glossar.md):
> beak, analyzer, Probe, Slot, Hüllkurve, Granular, SynthDef, Buffer, Step-Grid,
> Modulation, Look-ahead.

## Ausgangslage

Was schon da ist (Stand `main`):

- **Pixelfun** ist ein tixy-artiger Formelrenderer. Eine Formel bekommt Ort und Zeit
  hineingereicht und gibt eine Zahl zwischen −1 und +1 zurück:
  `f(x, y, nx, ny, nz, t, i, l, m, h) → [-1,1]`. Das passiert für jeden Pixel,
  30-mal pro Sekunde. Darüber liegen Transform-Backends (Sphere für Ringe, Flat für
  Wände), automatische Sweeps für Rotation, Zoom, Sway, Sättigung, und ein
  Preset-System, das in der Rotation läuft.
- **`l`, `m`, `h`** sind bereits Formelvariablen für tiefe, mittlere und hohe
  Frequenzen und werden vom **analyzer** geliefert.
- **beak** ist die Klangausgabe: ein separates C++-Programm mit **einem Ausgabekanal
  pro Panel**, das Samples abspielen und einfache Synthesetöne erzeugen kann.
- **Nation2026** ist ein Ring: **12 Panels à 8×8 px**, Ringradius 10 m, Publikum
  steht in der Mitte.

Der Stand in einem Satz: es gibt Ton, aber kein Werkzeug, um Ton und Bild
**zusammen zu gestalten**. Ton war bisher ein Anhängsel einzelner Apps.

## Leitidee: ein Takt, ein Raum, ein Feld

Drei Dinge, die sich Bild und Ton teilen. Das ist der ganze Trick.

### 1. Ein Takt — beide hören auf dieselbe Uhr

Heute läuft Pixelfun nach Sekunden: `t` ist die Zeit seit dem Start, die Formel
bewegt sich einfach vor sich hin. Musik läuft nach Takten und Schlägen.

Sobald beide Seiten **dieselbe** Uhr benutzen, passiert automatisch etwas Musikalisches:

- Ein Rotations-Sweep, der genau vier Takte für einen Hin-und-Her-Schwung braucht,
  ist eine **Phrase** — er endet dort, wo auch die Musik eine Zäsur hat.
- Ein Zoom, der über acht Takte ein- und ausatmet, atmet mit dem Stück.
- Ein Puls im Bild fällt auf denselben Moment wie ein Schlag im Ton — nicht
  „ungefähr", sondern exakt.

Praktisch heißt das: `t` bekommt einen Schalter. Entweder Sekunden (wie heute) oder
**Beats**. Bei Beats bedeutet `t = 4` schlicht „vier Schläge seit Loopbeginn", und
alle Intervalle werden in Takten angegeben statt in Sekunden.

Ohne diese gemeinsame Uhr driften Bild und Ton innerhalb weniger Minuten sichtbar
auseinander, egal wie sorgfältig man sie einzeln einstellt.

### 2. Ein Raum — der Ring ist ein Kreis aus Lautsprechern

Die zwölf Panels stehen auf einem Kreis mit 20 m Durchmesser, das Publikum in der
Mitte. Hinter jedem Panel sitzt ein Lautsprecher, und beak hat genau einen
Ausgabekanal pro Panel.

Damit gilt: **Panelnummer = Richtung = Klangort.** Panel 3 ist eine Richtung, in die
man schaut, *und* eine Richtung, aus der man hört. Wenn eine Welle im Bild von Panel
1 nach Panel 12 wandert, kann derselbe Wanderweg im Klang mitgehen — man hört die
Bewegung um sich herumlaufen.

Das kann kein Stereo-Setup und kein Laptop-Set: hier ist der Klangraum deckungsgleich
mit dem Bildraum, weil beide dieselbe physische Anordnung benutzen.

### 3. Ein Feld — dieselbe Formel steuert beides

Die Formel ist eine Funktion über Ort und Zeit. Für das Bild fragen wir sie an 768
Stellen ab (jeder Pixel), 30-mal pro Sekunde.

Nichts hindert uns daran, sie **zusätzlich an ein paar wenigen Stellen** abzufragen —
zum Beispiel in der Mitte jedes Panels. Das sind zwölf Zahlen pro Frame, praktisch
kostenlos. Diese zwölf Zahlen nennen wir **Probes** (Messstellen), und mit ihnen
steuern wir Klang: Lautstärke einer Stimme, Tonhöhe, Filter, oder als Auslöser für
einen Ton.

Der Unterschied zu „Bild vertonen": Es wird nichts nachträglich übersetzt. Bild und
Klang kommen aus **derselben Funktion**, nur an unterschiedlich vielen Stellen
abgefragt. Deshalb passen sie zwangsläufig zusammen — auch dann noch, wenn man die
Formel ändert.

## Die drei Kopplungsrichtungen

„Kopplung" heißt: was beeinflusst was. Es gibt drei mögliche Richtungen, und die
Oberfläche soll **alle drei gleich gut unterstützen** — nicht eine davon eingebaut
und die anderen als Bastellösung. (Das war mit „erstklassige Bürger" gemeint: jede
Richtung hat einen sichtbaren Platz im UI, nicht nur die, die zuerst fertig war.)

**A · Sound → Licht.** Der Klang bestimmt, wie das Bild aussieht. Ein Bassschlag
macht das Muster kurz heller. Das ist die klassische „Musikvisualisierung" und
existiert heute schon in einfacher Form über `l`, `m`, `h`.
*Neu:* Die Messwerte kommen aus unserer eigenen Klangengine statt von einem Mikrofon
draußen — also präziser, latenzfrei planbar und mit mehr als drei Zahlen (Onsets,
einzelne Stimmen, Hüllkurven).

**B · Licht → Sound.** Das Bild bestimmt, was klingt. Über die Probes: Wo die Formel
hell ist, ist die Stimme laut; wo eine Welle vorbeikommt, klingt ein Ton.
*Neu:* Das ist die eigentliche Idee dieses Projekts und geht heute nur, indem man es
in einer App fest programmiert.

**C · Partitur → beides.** Eine dritte Quelle steuert Bild und Ton gleichzeitig: das
Step-Grid (was klingt wann) und die Modulationsmatrix (was verändert sich langsam).
Ein Regler kann in derselben Zeile den Filter eines Klangs *und* den Zoom des Bildes
bewegen.
*Neu:* Genau dafür gibt es bisher kein Werkzeug.

In der Praxis mischt man alle drei. Eine typische Komposition: Grundpuls aus dem
Step-Grid (C), Drone-Lautstärken folgen dem Bild (B), und die Bildsättigung reagiert
leicht auf den Bass (A).

## Musikalische Form: Loop und Patch, keine Timeline

Bewusste Entscheidung, weil sie fast alles Weitere bestimmt:

- Die Installation läuft **in Rotation, über Stunden**. Das Publikum kommt und geht,
  niemand hört ein Stück von Anfang bis Ende. Eine DAW-Timeline mit Intro/Break/Drop
  hat hier keinen Adressaten.
- Was funktioniert, ist die Form eines guten Ambient-/Techno-Patches: ein Loop von
  4–16 Takten, darüber langsame Modulationen (30 s bis mehrere Minuten), die dafür
  sorgen, dass es sich nie exakt wiederholt.
- Deshalb: **Step-Grid** für Ereignisse plus **Modulationsmatrix** für Kontinuierliches
  — statt Clip-Timeline.

### „Rotation" — welche eigentlich?

Das Wort ist in diesem Projekt doppelt belegt, deshalb hier sauber getrennt:

- **Bild-Rotation** = das Muster dreht sich um den Ring (Parameter „Rotation" in der
  Szene, °/s).
- **Programm-Rotation** = die Installation wechselt von selbst durch ihre Inhalte
  durch. Das macht `InstallationTransport`: eine Warteschlange aus Einträgen, jeder
  läuft z. B. fünf Minuten, dann kommt der nächste.

Gemeint war die **zweite**. Die Aussage dahinter: Der große Spannungsbogen des
Abends entsteht dadurch, dass die Installation von Komposition A zu B zu C wechselt
— nicht dadurch, dass innerhalb einer Komposition ein Drama komponiert wird. Eine
Komposition ist ein **Zustand** (ein Loop, der atmet), die Rotation ist der
**Ablauf** (die Reihenfolge der Zustände).

## Klangmaterial

1. **Generiert** (SynthDefs) — beliebig modulierbar, leiert nie aus: Drones mit
   langsam wandernden Obertönen, gefilterte Rauschperkussion, gezupfte Saitenklänge
   (Karplus-Strong), FM-Glocken, granulare Wolken.
2. **Samples** — One-Shots, perkussives Material, Field-Recordings. Einmal in einen
   Buffer geladen, danach mit variabler Geschwindigkeit, Startpunkt, Hüllkurve oder
   granular abspielbar. Ablage: `octopus/priv/audio/…`.
3. **Externes Audio** (später) — Line-In, analysiert und in denselben Feature-Bus
   geschrieben. Dann ist ein DJ-Set die Modulationsquelle für den Ring.

## Fünf Zielbilder

Konkrete Szenen, an denen sich Engine und Oberfläche messen lassen. Wenn wir die
bauen können, stimmt das Fundament.

### 1 · Ring-Chase — „man hört das Bild wandern"

Eine Welle läuft um den Ring, z. B. `sin(x*0.5 - t)`. An jeder Panelmitte sitzt eine
Probe. Immer wenn der Wert dort von minus nach plus wechselt (der Wellenkamm passiert
gerade), spielt der Lautsprecher **dieses** Panels einen kurzen perkussiven Ton.

Effekt: Das Geräusch läuft im selben Tempo und in derselben Richtung um das Publikum
herum wie das Licht. Ändert man die Formel — schneller, andersherum, zwei Wellen
gegeneinander — ändert sich der Klang mit, ohne dass man am Ton etwas anfasst.

Warum zuerst: Es ist trivial zu bauen und testet die komplette Kette (Probe →
Schwellwert → Note → Kanal → Lautsprecher). Und es ist sofort überzeugend.

### 2 · Voicing-Drone — „das Bild ist der Akkord"

Zwölf liegende Stimmen, eine pro Panel, jede auf einer festen Tonhöhe aus einer
Skala. Die Lautstärke jeder Stimme folgt kontinuierlich dem Probe-Wert ihres Panels.

Effekt: Wo das Muster gerade hell ist, ist die zugehörige Tonhöhe hörbar; wo es
dunkel ist, verschwindet sie. Der Akkord ändert sich, weil sich das Bild ändert.
Zoomt man heraus (feineres Muster), flackern mehr Stimmen gleichzeitig kurz auf und
es wird dichter; zoomt man hinein, bleiben zwei, drei Töne stehen. Man spielt
Harmonik, indem man an der Grafik dreht.

### 3 · Sample-Kammern — „jeder Ort klingt anders"

Pro Panel läuft ein eigener Sample-Loop leise durch. Der Probe-Wert steuert nicht
das Ein/Aus, sondern **Klangfarbe**: Filter-Cutoff und Abspielgeschwindigkeit.

Effekt: Ein sehr langsam rotierendes Muster wird zu einem wandernden Raum. Man geht
im Ring herum und hört an jeder Stelle eine andere Version desselben Materials.

### 4 · Beat-locked Breath — „das Bild atmet im Takt"

Kein neues Klangmaterial, nur Zielbild 1 oder 2 plus: Die Auto-Sweeps von Zoom und
Rotation rasten auf 4 oder 8 Takte ein statt auf Sekunden.

Effekt: Das Bild bewegt sich nicht sichtbar „im Takt" (es blinkt nichts), aber jede
Bewegung endet dort, wo der Loop endet. Man merkt es vor allem, wenn es fehlt.
Testet die gemeinsame Uhr.

### 5 · Onset-Blitz — „der Ton schlägt zurück"

Die Gegenrichtung: Die Klangengine meldet, wann ein Ton anfängt (Onset) und wie laut
die Bässe gerade sind. Diese Werte heben kurz Sättigung oder Helligkeit an.

Effekt: Das Bild bekommt Akzente, die aus dem Klang kommen — sparsam eingesetzt der
Unterschied zwischen „läuft nebeneinander her" und „gehört zusammen". Weil die Werte
aus unserer eigenen Engine kommen (nicht aus einem Mikrofon), wissen wir sie sogar
schon **vorher** und können sie exakt auf den Frame legen.

## Kalibrierung und Sorgfaltspflichten

### AV-Offset — Bild und Ton wirklich gleichzeitig

Bild und Ton brauchen unterschiedlich lange, bis sie beim Publikum ankommen:

- Das Bild wird 30-mal pro Sekunde gerechnet (ein Frame alle ~33 ms), geht per UDP
  an die ESP32-Panels und wird dort ausgegeben.
- Der Ton läuft durch Audiopuffer der Soundkarte (typisch 10–25 ms).

Die Differenz ist **konstant** — sie schwankt nicht, sie ist nur unbekannt. Also
misst man sie einmal ein: einen scharfen Blitz gleichzeitig mit einem Klick
auslösen, schauen/hören, was zuerst kommt, und mit einem einzigen Regler
(**AV-Offset**, in Millisekunden, positiv wie negativ) verschieben, bis es deckt.
Der Wert wird gespeichert und gilt ab dann für alles.

Ohne ihn wirkt selbst perfekt synchrone Komposition „leicht daneben", und niemand
kann benennen, warum.

### Lautheit — die Grenzen gehören ins System

- **Master-Limiter**: eine harte Obergrenze am Ausgang. Eine Formel, die versehentlich
  zwölf Stimmen gleichzeitig auf voll dreht, darf keinen Schaden anrichten.
- **Nachtabsenkung**: automatisch leiser ab einer Uhrzeit.
- **Panic**: ein Knopf, der jeden Ton sofort abbricht und alle Kanäle stummschaltet.
  Pflicht bei allem, was programmiert klingt — sonst hat man irgendwann einen
  Dauerton, den man nur noch per Stromstecker loswird.

Diese Grenzen gehören in die Engine, nicht in die Disziplin der Person am Rechner.
