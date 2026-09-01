# Pixelfun Audiovisuell

Arbeitsstand auf Branch `feat/pixelfun-audiovisual`. Noch kein Code — nur Konzept,
Architektur und UI-Spezifikation als gemeinsame Diskussionsgrundlage.

| Dokument | Inhalt |
|---|---|
| [00-glossar.md](00-glossar.md) | **Hier anfangen.** Was beak, analyzer, Probe, Hüllkurve, SynthDef … bedeuten |
| [01-konzept.md](01-konzept.md) | Leitidee, Kopplungsrichtungen, musikalische Form, Zielbilder |
| [02-architektur.md](02-architektur.md) | SuperCollider vs. beak, Prozessbaum, Timing, Deployment, Risiken |
| [03-ui.md](03-ui.md) | Composer-Oberfläche `/studio`: Zonen, Interaktionen, Ausbaustufen |
| [04-offene-fragen.md](04-offene-fragen.md) | Entschieden — und was noch offen ist |
| [05-spaeter.md](05-spaeter.md) | Bewusst zurückgestellte Features |
| [06-fahrplan.md](06-fahrplan.md) | Reihenfolge der Umsetzung, M0 bis M8 |
| [07-hardware-prototyp.md](07-hardware-prototyp.md) | Audio-Hardware für den Schreibtisch |
| [08-testplan.md](08-testplan.md) | Manuelle Testfälle zum Abhaken |
| [studio-entwurf.html](studio-entwurf.html) | Der UI-Entwurf zum Anschauen — im Browser öffnen |

## Kurzfassung

- **Klangengine:** SuperCollider (`scsynth`) über OSC, Elixir bleibt Kompositions-
  und Sequencer-Schicht. `beak` bleibt für alle Bestands-Apps unangetastet.
- **Zeit:** ein einziger musikalischer Transport (BPM, Bar/Beat) treibt Bild *und*
  Ton. Pixelfun-`t` wird optional beat-gebunden.
- **Raum:** der Ring hat 12 Panels — und pro Panel einen Kanal. Panelindex =
  Azimut = Lautsprecher. Die räumliche Verteilung des Bildes *ist* das Klangbild.
- **Form:** Loop + Patch + Modulation, keine DAW-Timeline. Die Installation läuft
  in Rotation, stundenlang, das Publikum wechselt.
- **Zwei Ebenen:** `/studio` baut *eine* Komposition; was wann läuft, entscheidet die
  bestehende Konsole auf `/` (Warteschlange, Rotation, Übernahme) — keine neue Seite.
- **Oberfläche:** eine LiveView-Seite `/studio` — Ring-Preview mittig, Szene links,
  Klang rechts, Kopplung (Step-Grid + Mod-Matrix) unten, Transport oben.
