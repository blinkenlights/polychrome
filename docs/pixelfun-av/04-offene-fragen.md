# 04 — Entscheidungen und offene Fragen

## Entschieden

| # | Frage | Entscheidung |
|---|---|---|
| 1 | Zielinstallation | **Ring (Nation2026)** zuerst. Wand-Installationen später. |
| 2 | Kanalzuordnung | **Kanal n → Panel n**, also Azimut = Klangort. Hardware noch offen, Zuordnung gesetzt. |
| 3 | Komponier-Metapher | **Step-Grid + Modulationsmatrix** (Loop/Patch), keine DAW-Timeline. |
| 4 | Anzahl Slots | **8**. |
| 5 | Loop-Länge / Polymeter | Zunächst **eine gemeinsame Loop-Länge**, fest verdrahtet. Unterschiedliche Längen später ([05-spaeter.md](05-spaeter.md)). |
| 6 | Szeneneditor | Bleibt eine **eigene Seite**; das Studio **referenziert** Szenen, statt sie zu duplizieren. |
| 7 | Sample-Verwaltung | Zunächst **per Deployment ausliefern**, kein Upload über die Weboberfläche. |
| 8 | Vorhören über Kopfhörer | **Nein** — später. |
| 9 | Externes Audio / Line-In | **Nein** — später. |
| 10 | Aufnahme / Mitschnitt | **Nein** — später. |
| 11 | Mehrbenutzerbetrieb | **Ein Bedienplatz.** Keine Konfliktauflösung. |
| 12 | Zeit-/Lautstärkeprofile | **Keine Auflagen am Ort.** Master-Limiter bleibt trotzdem, als Schutz vor eigenen Fehlern. |
| 13 | Crowd/Radar als Quelle | Zunächst **raus** aus den Zielbildern — später. |
| 14 | Ebene über dem Studio | **Keine neue Seite.** Warteschlange, Rotation, Übernahme und Übergangsdauer liegen bereits in `InstallationTransport` und der Konsole auf `/`; Kompositionen reihen sich dort als Einträge ein. Der Performance-/Live-Mix-Modus ist die aufgeräumte Ansicht dieser Ebene. |
| 15 | MIDI-Controller | **Vorhanden** (Keyboard und Pads). Wird über die Modulationsmatrix angebunden, sobald die steht. |

## Offen — blockiert die Architektur

**A · Audio-Hardware und Zielrechner.**
Auf welcher Maschine läuft der Ton in Nation2026 — derselbe Pi wie Octopus oder eine
eigene Kiste? Welches Interface mit wie vielen Ausgängen? Davon hängt ab, ob
SuperCollider überhaupt eine Option ist. *Aktueller Stand: steht noch nicht fest.*

**B · beak-Zukunft.**
beak bedient heute mehrere Bestands-Apps (`encounter`, `senso`, `lemmings`,
`space_invaders`, `rickroll`, `text`). Solange die weiterlaufen sollen, gilt: eine
Soundkarte kann in der Praxis nur **ein** Programm exklusiv bespielen. Also entweder
beak *oder* SuperCollider zur selben Zeit — mit einem klaren Umschaltpunkt beim
App-Wechsel. Zu entscheiden, sobald A geklärt ist.

**C · Betrieb von SuperCollider.**
Wer sorgt dafür, dass `scsynth` nach einem Neustart wieder läuft? Optionen und
Aufwand siehe unten.

## Offen — Gestaltung

**D · Übergänge zwischen Kompositionen.**
Der Vorschlag steht ausgearbeitet in [03-ui.md](03-ui.md) („Übergänge"): Wechsel auf
der Taktgrenze, Bild über die vorhandenen Transitions, Ton als Überblendung über
N Takte mit gleichzeitigem Klingen beider Kompositionen. Zu entscheiden bleibt, was
bei **unterschiedlichem Tempo** passieren soll — Tempofahrt über die Überblendung
oder harter Schnitt.

**E · Mehrere Szenen innerhalb einer Komposition.**
Soll eine Komposition zwischen mehreren Pixelfun-Szenen wechseln können (alle 8
Takte eine andere), oder bleibt es bei einer Szene pro Komposition? Vorschlag:
Datenmodell erlaubt eine Liste, MVP füllt sie mit genau einem Eintrag.

## Betrieb von SuperCollider — die Optionen im Klartext

`scsynth` ist ein Programm, das dauerhaft laufen und nach Stromausfall von allein
wiederkommen muss. Der Aufwand dafür ist überschaubar, aber er ist nicht null:

| Weg | Was zu tun ist | Aufwand | Risiko |
|---|---|---|---|
| **systemd-Dienst auf dem Zielrechner** (empfohlen) | Paket installieren, eine Unit-Datei mit Audiogerät und Kanalzahl anlegen, aktivieren | einmalig ~1 Std., dann selbsttragend | gering; Neustart und Logs übernimmt das System |
| **Von Octopus gestartet** (als Kindprozess) | Octopus startet und überwacht `scsynth` selbst | mittel | Octopus muss Audiogerätefehler behandeln — vermischt zwei Zuständigkeiten |
| **Im Docker-Container** | Container braucht Zugriff auf `/dev/snd` und Realtime-Priorität | hoch | Audio in Containern ist erfahrungsgemäß Ärger; nicht empfohlen |
| **Gar nicht — bei beak bleiben** | nichts | keiner | Timing bleibt ungenau, Klangvielfalt begrenzt |

Der wichtige Punkt: **Wir müssen das nicht jetzt entscheiden.** Die geplante
Engine-Schicht in Elixir spricht mit beiden Backends. Wir können mit beak anfangen,
die ganze Oberfläche bauen und komponieren — und SuperCollider dann dazunehmen,
wenn Rechner und Hardware feststehen. Fällt SC später aus (Gerät kaputt, Dienst
tot), läuft der AV-Modus mit beak weiter, nur mit ungenauerem Timing.
