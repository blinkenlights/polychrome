# Ear

Hört den Ring über Kopfhörer, als stünde man drin.

scsynth spielt einen Kanal pro Panel. Ear liest die zwölf Kanäle über ein
Loopback-Gerät, setzt jeden als Monoquelle an die Stelle seines Panels und
rendert binaural (HRTF, `AVAudioEnvironmentNode`). In der Draufsicht wird der
Hörer verschoben und gedreht.

```
octopus ──OSC──▶ scsynth -o 12 -H "BlackHole 16ch"
                          │ 12 Kanäle
                          ▼
Ear   Capture-Engine: BlackHole → AVAudioSinkNode → Ringpuffer (C)
      Playback-Engine: 12 × AVAudioSourceNode → AVAudioEnvironmentNode → Kopfhörer
      Geometrie: GET /api/sound/speakers  (sonst eingebauter Nation-2026-Ring)
```

## Einmalig

```bash
brew install blackhole-16ch
```

Der Treiber braucht ein Admin-Passwort und danach eventuell einen Neustart von
Core Audio oder dem Rechner. Beim ersten Start mit BlackHole fragt Ear nach der
Mikrofon-Freigabe. Die ist nötig, weil jedes Eingabegerät, auch ein virtuelles,
als Mikrofon zählt.

Die Systemausgabe muss auf den Kopfhörern bleiben. Steht sie auf BlackHole,
hört Ear sich selbst, und die App warnt.

## Starten

```bash
cd ear && make run
```

Danach octopus mit einem Kanal pro Panel starten:

```bash
cd octopus && SOUND_SPATIAL=1 iex -S mix phx.server
```

`SOUND_DEVICE` wählt ein anderes Gerät als `BlackHole 16ch`. Läuft scsynth noch
vom Stereo-Betrieb, übernimmt octopus es unverändert. Dann scsynth vorher
beenden, zum Beispiel mit `pkill scsynth`.

## Bedienen

- **Hörer ziehen:** gehen.
- **Griff an der Nase ziehen** oder **scrollen:** drehen. Mit Shift rastet der Winkel auf 15°.
- **Doppelklick:** zurück auf die Plattformmitte, Blick nach Norden.
- **Panel antippen:** spielt genau dort einen Ping.
- **Ping reihum:** ein Klick pro Kanal im Uhrzeigersinn ab Norden. Er kommt aus Ear selbst, ohne scsynth. Wandert er nicht mit dem leuchtenden Panel, stimmt die Orientierung nicht.
- **Kopfbewegung:** dreht den Kopf langsam um ±7°, wenn kein Headtracking da ist.
- **Headtracking:** folgt der echten Kopfdrehung der AirPods.
- **Hall, Abstand, Pegel:** Hallanteil, Abfall mit der Entfernung ab 2 m, Gesamtlautstärke.

## Wenn alles hinter dir klingt

Das ist normal und kein Fehler in der Zuordnung. Eine generische HRTF entscheidet
vorne gegen hinten nicht zuverlässig; viele Menschen hören vorne als hinten. Ein
Offline-Rendering bestätigt, dass die Richtungen stimmen: eine Quelle vorne kommt
lauter und heller heraus als dieselbe Quelle hinten, und links/rechts trennt um
etwa 15 dB.

Was hilft:

- **Kopfbewegung einschalten.** Die kleine Drehung liefert genau den Hinweis, den
  die Ohren zum Auflösen brauchen.
- **Hall herunterdrehen.** Diffuse Energie verdeckt die Ohrmuschel-Hinweise.
- **Selbst drehen**, also den Griff an der Nase ziehen, und darauf achten, wie das
  Klangbild mitgeht.

- **Headtracking einschalten**, wenn Kopfhörer mit Bewegungssensor da sind: AirPods
  Pro (beide Generationen), AirPods 3, AirPods Max, Beats Fit Pro. Beim ersten Mal
  fragt macOS nach Bewegungsdaten. „Geradeaus neu setzen" nimmt die aktuelle
  Kopfhaltung als Blickrichtung. Dreht sich das Bild falsch herum, hilft
  „Richtung umkehren".

Am zuverlässigsten ist Headtracking: Die Drehung ist die eigene, und das Gehirn
glaubt einer selbst verursachten Bewegung.

Die Statuszeile zeigt, wie der Ringpuffer zwischen den beiden Audio-Clocks
arbeitet. *Aussetzer* heißt, er lief leer, *Sprünge* heißt, er lief über. Beides
kommt vor, wenn die Clocks auseinanderlaufen. Zählt es schnell hoch, stimmt
etwas mit den Blockgrößen nicht.

## Entwickeln

```bash
swift test
```

- `Sources/EarRing`: Ringpuffer in C. Alle Quellen eines Render-Zyklus lesen denselben Ausschnitt, damit die Kanäle nicht gegeneinander verrutschen.
- `Sources/EarKit`: Geometrie, Geräte, Capture, Renderer.
- `Sources/Ear`: SwiftUI-App.

Die Zuordnung von Kanal zu Panel legt octopus fest (`Octopus.Sound.Speakers`),
nicht Ear. Der eingebaute Ring spiegelt sie nur für den Fall, dass octopus
nicht läuft.
