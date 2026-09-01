# 07 — Audio-Hardware für den Schreibtisch-Prototypen

Ausgangslage: Displays und Elixir-Server laufen bereits. Es fehlt nur die Tonseite.
Ziel ist **nicht** eine kleine Version der Installation, sondern das kleinste Setup,
an dem man hört, ob die Kopplung funktioniert.

## Stufe 0 — nichts kaufen

Der Laptop hat Stereo. Damit lässt sich bereits prüfen, ob ein Ton im richtigen Moment
kommt und ob sich Bild und Ton gemeinsam bewegen — nur eben nur links/rechts statt im
Kreis. beak hat dafür sogar einen Simulationsschalter (`-s`), der für die Live-View-
Arbeit auf Stereo herunterrechnet; SuperCollider startet ohnehin einfach mit `-o 2`.

**Damit sollten M0 bis M3 aus dem [Fahrplan](06-fahrplan.md) gebaut werden.** Erst
wenn das steht, lohnt Hardware — dann weiß man auch, was man wirklich braucht.

## Stufe 1 — vier Kanäle (die empfohlene Prototyp-Stufe)

Vier Kanäle sind die Schwelle, ab der Räumlichkeit entsteht: vier kleine Lautsprecher
im Rechteck oder Kreis um den Sitzplatz, und eine Bewegung im Bild wandert hörbar um
einen herum. Für einen Schreibtisch reicht das vollkommen; zwölf Kanäle beweisen
nichts, was vier nicht auch beweisen.

### Was man braucht

| Teil | Konkret | ungefähr |
|---|---|---|
| **Audio-Interface mit 4 Ausgängen** | Behringer UMC404HD (4 In / 4 Out, USB, class-compliant — läuft ohne Treiber an Mac und Linux) | 130–160 € |
| **Verstärker** | 2× Class-D-Modul „PAM8403" (je 2 Kanäle, 2×3 W, Strom per USB) — winzig, für Zimmerlautstärke völlig ausreichend | je 3–6 € |
| **Lautsprecher** | 4× Breitband-Chassis, z. B. Visaton K 50 (5 cm) oder FRS 8 (8 cm), alternativ Dayton Audio CE-Serie. Kein Hochtöner, keine Weiche nötig | je 6–15 € |
| **Kabel** | 4× Klinke/Cinch vom Interface an die Amp-Eingänge, Lautsprecherkabel | ~10 € |

Summe: grob **170–220 €**, davon ist das Interface der Kostentreiber.

Die Chassis kann man erst mal offen auf den Tisch legen; für einen brauchbaren
Klang genügen später vier kleine geschlossene Kistchen (Holz, ~0,5 l). Bässe braucht
dieser Prototyp nicht.

### Billigere Variante (nur macOS)

Statt eines Interfaces mehrere **USB-Audio-Sticks** (je ~8 €, Stereo) und daraus im
Audio-MIDI-Setup ein **Aggregate Device mit Driftkorrektur** bauen: vier Sticks = acht
Kanäle für ~30 €. Klanglich mäßig und unter Linux fummelig, aber für „klingt es an
der richtigen Stelle?" völlig ausreichend. Unter Linux würde ich das **nicht**
versuchen — dort ist ein einziges Mehrkanal-Interface deutlich weniger Ärger.

## Stufe 2 — acht bis zwölf Kanäle

Erst sinnvoll, wenn der Ring wirklich nachgebaut werden soll:

| Teil | Konkret |
|---|---|
| **Interface** | ESI Gigaport HD+ (8 analoge Ausgänge, USB, class-compliant, günstig und in Installationen verbreitet) oder Behringer UMC1820 (8 Ausgänge, mit XLR-Eingängen) |
| **Verstärker** | 4–6× TPA3116D2-Module (je 2×50 W, 12–24 V Netzteil), wenn es lauter werden soll — sonst weiter PAM8403 |
| **Lautsprecher** | 8–12× Visaton FRS 8 oder vergleichbar |

Bei zwölf Kanälen wird die Verkabelung der eigentliche Aufwand, nicht die Elektronik.

## Was ich **nicht** empfehlen würde

- **Zwölf aktive Mini-Lautsprecher** (PC-Boxen): zwölf Netzteile, zwölf
  Lautstärkeregler, kein gemeinsamer Pegel. Wird im Betrieb zur Qual.
- **Ton über die ESP32s an den Panels** (I2S-Verstärker wie MAX98357A). Verlockend,
  weil pro Panel schon ein Mikrocontroller sitzt — aber mehrere ESP32 sample-genau
  zueinander zu synchronisieren ist ein eigenes Projekt. Für Perkussion würde man die
  Ungenauigkeit hören.
- **Bluetooth-Lautsprecher**: Latenz von 100–200 ms, schwankend. Damit ist jede
  Aussage über audiovisuelle Synchronität wertlos.

## Anschluss an die Software

Der Kanalbegriff ist überall derselbe: **Kanal n = Panel n**. Beim Start der Engine
gibt man einfach die Kanalzahl an (`beak … -o 4` bzw. `scsynth -o 4`), und in der
Konfiguration steht, wie viele Panels der Prototyp hat. Das Studio zeigt dann vier
Pegelmeter statt zwölf — sonst ändert sich nichts. Deshalb skaliert der Prototyp
später ohne Umbau auf den Ring hoch.
