# Collective

Octopus-App, die mehrere Animationen auf Basis der Bewegungs- und Positionsdaten
der Menschen im Ring rendert.

## Datenquelle

Die App konsumiert den **Radar-PubSub-Feed** (`Octopus.Radar.subscribe()`,
`{:radar_frame, device_id, %Frame{tracks: [...]}}`). In dev wird dieser Feed vom
**Mock-Radar** erzeugt:

- `Octopus.Apps.Collective.MockCrowd` — simuliert wandernde Personen im Ring.
  Person-Format spiegelt `Octopus.Radar.Track` (`x, y, vx, vy` in Metern / m/s,
  Ursprung = Ring-Zentrum). Verhalten (portiert aus `humanWorld.ts`): **autonome
  Population 1-20** (Leute kommen/gehen, Zielzahl re-rollt alle paar Sekunden),
  **wander + idle** (laufen, kurz stehen, neues Ziel) und **Gruppen** (ab und zu
  versammelt sich ein Cluster an einem Punkt und steht eine Weile zusammen still).
- `Octopus.Apps.Collective.MockRadar` — GenServer, der die MockCrowd tickt und als
  `%Frame{}` aufs echte Radar-Topic broadcastet. Dadurch sehen **dieselbe Crowd**:
  die 3D-Sim (`/sim3daframe`, Humans → „Radar (live)"), die Collective-Animationen,
  `RadarLive` usw.

Gestartet wird MockRadar nur in dev (`config :octopus, :radar_mock, enabled: true`,
override via `RADAR_MOCK`) und nur, wenn **kein echter Sensor-Port** vorhanden ist
(Auto-Abschaltung in `Octopus.Application`). Sobald Tims Mockserver oder echte
Hardware aufs selbe Topic broadcastet, wird MockRadar einfach nicht gestartet — die
Animationen laufen unverändert weiter.

Der Slider `Mock Movement` der App proxiet zur Laufzeit an MockRadar (globaler
Tempo-Multiplikator; no-op gegen echte Daten). Die Population ist autonom — kein
Count-Slider.

## Animationen

Jede Animation implementiert das `Octopus.Apps.Collective.Animation`-Behaviour
(`name/0`, `init/1`, `render/4`) und liegt unter
`octopus/lib/octopus/apps/collective/animations/`.

### In Arbeit

- **Bewegungs-Sturm** (`Kollektiv`) — Gesamtbewegungsenergie aller Personen wird
  summiert. Alle stehen: Stille, kaum Licht, Sterne. Alle laufen: Sturm, Blitze,
  chaotische Energieausbrüche über alle Panels. Die Crowd kontrolliert das Wetter
  des Raums. *Keine Einzel-Zuordnung nötig — guter erster Pipeline-Test.*

### Backlog

#### Sozial

- **Spinnennetz / Tension strings** — Zwischen je zwei Personen spannt sich ein
  Lichtfaden. Je näher, desto heller/breiter. Bei Berührung: Blitz/Farbexplosion.
  Mit 10 Personen: 45 gleichzeitige Verbindungen → lebendiges Mandala.
- **Tauziehen / Tug of light** — Ein heller Lichtball auf dem Ring. Jede Person
  zieht ihn magnetisch zu sich; der Ball folgt dem Schwerpunkt aller Kräfte.
  Gruppen dominieren, Einzelgänger kaum. Erzeugt echte Gruppeninteraktion.
- **Rollen-Erkennung** — Verhaltensmuster klassifizieren: Wanderer (viel Bewegung)
  orange-feurig, Steher/Inseln (kaum Bewegung) ruhige blaue Anker, Cluster
  pulsieren lila. Das soziale Ökosystem wird sichtbar.

#### Physik

- **Voronoi-Territorien** — Jede Person besitzt die ihr nächsten Panels; ihr
  Territorium leuchtet in ihrer Farbe. Bewegung verschiebt Grenzen in Echtzeit.
  An Territoriengrenzen: lebhafter Kampf-Effekt. Gruppen verschmelzen zu
  Farbblöcken.
- **Welleninterferenz** — Jede Person sendet kontinuierlich kreisförmige Wellen
  aus. Konstruktive Interferenz = heller Punkt, destruktive = dunkel. Muster ist
  einzigartig für die Konstellation; ändert sich, wenn nur eine Person sich bewegt.

#### Kollektiv

- **Crowd breath / Atemsystem** — Der Ring atmet; Pulsfrequenz/Amplitude hängen
  von der Gesamtdichte ab. Viele = schneller intensiver Puls, wenige =
  langsames meditatives Atmen. Funktioniert auch mit simpler Radarauswertung.
- **Schwarm-Schwerpunkt** — Geometrischer Mittelpunkt (Centroid) aller Personen
  wird mit besonderem Licht markiert. Stehen alle auf einer Seite, kippt die
  Animation. Gleichmäßige Verteilung = Harmonie, Ungleichgewicht = Spannung.

#### Reaktiv

- **Personen als Instrumente** — Jede Person bekommt beim Eintreten Farbe +
  Rhythmus; ihr Lichtmuster pulsiert darin → visuelle Polyrhythmik. Nahe
  Personen synchronisieren ihre Rhythmen graduell (Firefly synchronization).
- **Kollektive Schleifenpfade** — Jede Person hinterlässt eine verblassende Spur.
  Häufig genutzte Pfade akkumulieren zu hellen Trampelpfaden, einmalige verblassen.
  Das Bewegungsgedächtnis des Abends entsteht sichtbar.
