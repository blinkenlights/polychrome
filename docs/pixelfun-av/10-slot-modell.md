# 10 — Was ein Slot ist

Denkpapier, kein Bauplan. Anlass: Sind die acht Grid-Zeilen und die Klangspalte
dasselbe — und wo gehören Ring-Chase und Drone hin?

## Was im Entwurf steht

Nicht aus der Erinnerung, sondern aus [studio-entwurf.html](studio-entwurf.html):

**Die Klangspalte listet acht Slots**, jeder mit einem Typ:

| | | |
|---|---|---|
| 1 Drone | synth | 5 Klick · sample |
| 2 Ping | synth | 6 Glocke · synth |
| 3 Feld A | sample | 7 Wolke · granular |
| 4 Bass | synth | 8 — · leer |

**Das Grid zeigt dieselben Slots.** Im Entwurf sind es die Zeilen Ping, Bass,
Feld A und Drone — und die beiden letzten sind nicht leer, sondern als
**gehaltener Balken** über die ganze Zeile gezeichnet.

**Das Detailfeld** unter der Liste zeigt für den gewählten Slot: SynthDef,
Tonhöhe, Filter, Release — und **„Kanal: folgt Probe"**.

Daraus folgt eine Antwort, die ich in meiner Frage gar nicht angeboten hatte:
**Ring-Chase ist im Entwurf kein Instrument.** Es ist der Slot „Ping", dessen
Kanal der Probe folgt und der vom Nulldurchgang ausgelöst wird. Und der Drone
ist Slot 1 — ein Slot, der gehalten wird statt angeschlagen.

## Das Modell dahinter

Ein Slot besteht aus drei Dingen, und alles, was wir heute haben, fällt darunter:

**1 · Klang** — SynthDef oder Sample, dazu Tonhöhe, Filter, Länge.

**2 · Auslöser** — was ihn zum Klingen bringt:
- *Grid* — die Schritte im Raster
- *Probe-Nulldurchgang* — wenn die Welle ein Panel passiert
- *gehalten* — klingt dauernd, die Lautstärke wird moduliert
- später: MIDI-Pad, eine Matrixzeile

**3 · Ort** — auf welchem Kanal:
- *festes Panel*
- *folgt Probe* — der Kanal, an dem gerade ausgelöst wurde
- *alle Panels* — eine Stimme je Panel gleichzeitig
- *rotiert um n* je Auslösung

Damit sind unsere beiden Instrumente keine Sonderfälle mehr:

| | Klang | Auslöser | Ort |
|---|---|---|---|
| **Ring-Chase** | pc_ping | Probe-Nulldurchgang | folgt Probe |
| **Drone** | pc_voice | gehalten | alle Panels |
| **Grid-Zeile** | beliebig | Grid | Panel aus dem Schritt |

## Was dadurch möglich wird, das heute nicht geht

Das ist das eigentliche Argument, nicht die Aufräumerei:

- **Zwei Chases gleichzeitig** mit verschiedenen Klängen und verschiedenen
  Mindeststeilheiten — einer als tiefer Puls, einer als Glitzern obendrauf.
- **Ein Drone auf dem halben Ring**, während die andere Hälfte perkussiv bleibt.
- **Ein Sample vom Bild ausgelöst** statt vom Raster: Field-Recording-Schnipsel,
  die dort anspringen, wo die Welle vorbeikommt.
- **Ein Grid-Schlag, der der Probe folgt** statt auf einem festen Panel zu
  sitzen — der Rhythmus kommt aus dem Raster, der Ort aus dem Bild.

Heute ist jede dieser vier Sachen unmöglich, weil Chase und Drone jeweils genau
eine fest verdrahtete Kombination sind.

## Was nicht sauber aufgeht

Ehrlich, weil es die Entscheidung beeinflusst:

- **Ein Slot ist dann nicht mehr immer eine Stimme.** „Alle Panels" heißt zwölf
  Stimmen gleichzeitig, jede mit eigener Lautstärke. Das Modell muss das
  aushalten, sonst passt der Drone nicht hinein.
- **Auslöser haben eigene Einstellungen.** Die Mindeststeilheit gehört zum
  Probe-Auslöser, nicht zum Klang; die Wiederholsperre auch. Slots brauchen also
  eine kleine auslöserabhängige Einstellungsgruppe — kein Drama, aber kein
  flaches Datenmodell mehr.
- **Mehr Indirektion für den einfachen Fall.** „Ich will nur einen Klick auf
  jeder Eins" führt dann durch drei Entscheidungen statt durch eine.
- **Umbau von Chase und Drone.** Beide laufen heute als eigene Prozesse und
  funktionieren. Sie würden zu Implementierungen von Auslösern und Orten.

Der Umbau hat allerdings einen Nebengewinn, der auf der Mängelliste steht:
**Kompositionen speichern dann alles**, weil Chase und Drone keine Zustände
neben dem Muster mehr wären, sondern Teil davon
([09-luecken.md](09-luecken.md), B7).

## Panel je Schritt oder je Slot?

Der Entwurf setzt den Kanal **am Slot** („Kanal: folgt Probe"). Gebaut ist er
**am Schritt** — jede Zelle trägt ihr Panel, und das hat sich beim Testen als
gut erwiesen (F5).

Beides schließt sich nicht aus: Der Slot legt die **Regel** fest, der Schritt
darf sie **überschreiben**. Ein Slot auf „festes Panel 3" spielt auf 3, außer
wo im Raster ausdrücklich etwas anderes steht. Ein Slot auf „folgt Probe"
ignoriert die Schrittangabe, weil sein Ort aus dem Bild kommt.

## Zu entscheiden

1. **Slot = Instrument = Grid-Zeile?** Der Entwurf sagt ja. Empfehlung: ja —
   wegen der vier Dinge oben, nicht wegen der Ordnung.
2. **Bleiben die Schnellschalter?** Heute schaltet man Drone und Ring-Chase mit
   einem Klick an. Im Slot-Modell wäre das „Slot 1 als Drone einrichten". Bequem
   ist der Schalter; ehrlich ist der Slot. Vorschlag: Schalter bleiben als
   Voreinstellung, die einen Slot füllt.
3. **Auslöser-Vorrat.** Fangen wir mit den drei vorhandenen an (Grid, Probe,
   gehalten) oder gleich mit MIDI-Pad und Matrixzeile?
4. **Wie viele Slots wirklich?** Acht ist gesetzt — aber ein Drone auf „alle
   Panels" belegt zwölf Stimmen. Bei vier solchen Slots sind das 48 gehaltene
   Stimmen. Bei SuperCollider kein Problem, bei beak schon.
