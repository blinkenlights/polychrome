# 05 — Später (bewusst zurückgestellt)

Ideen, die gut sind, aber nicht in die erste Ausbaustufe gehören. Hier festgehalten,
damit sie nicht verloren gehen — und damit das Datenmodell sie nicht von vornherein
unmöglich macht.

| Thema | Warum zurückgestellt | Was wir jetzt schon offenhalten sollten |
|---|---|---|
| **Crowd als Modulationsquelle** — Radar-Tracks (Anzahl und Bewegung der Menschen im Ring) steuern Dichte, Register, Lautstärke | Zusätzliche Datenquelle mit eigener Unsicherheit; erst soll das Grundinstrument stehen | Die Modulationsmatrix nimmt beliebige Quellen entgegen — Radar wird später einfach eine weitere Zeile |
| **Externes Audio / Line-In** — ein DJ-Set oder Umgebungsklang als Modulationsquelle | Braucht Eingangshardware und eine zweite Analysekette | Der Feature-Bus ist quellenunabhängig; ein Line-In-Analyzer schreibt später in denselben Bus |
| **Cue-Bus / Vorhören über Kopfhörer**, während die Installation läuft | Braucht einen zweiten Ausgabeweg und ein zweites Gerät | In SC ein zusätzlicher Bus; kein Umbau der Slots nötig |
| **Sample-Upload über die Weboberfläche** (statt Ausliefern per Deployment) | Deployment ist für den Anfang einfacher und sicherer | Samples werden über eine Registry angesprochen, nicht über Pfade im Preset — Upload kann später dieselbe Registry füllen |
| **Polymeter** — Slots mit unterschiedlichen Loop-Längen | Macht Grid und Scheduler deutlich komplizierter | Loop-Länge wird pro Slot gespeichert, zunächst überall gleich gesetzt |
| **Mehrbenutzerbetrieb** — zwei Leute gleichzeitig im Studio | Konflikte sind viel Arbeit für wenig Nutzen | Zunächst: letzter gewinnt, mit sichtbarem Hinweis, wenn jemand anderes verbunden ist |
| **Aufnahme / Mitschnitt** (Audio + Frames) für Dokumentation | Zusätzliche Schreibpfade, Speicherbedarf, Formatfragen | Die Engine kennt einen Master-Bus — der ist später der natürliche Abgriff |
| **Zeit- und Lautstärkeprofile** (Nachtabsenkung, Auflagen) | Aktuell keine Anforderung am Ort | Master-Gain sitzt an einer Stelle, nicht in jedem Slot |
| **Nicht-Ring-Installationen** (Woodstock, Pixie) | Der räumliche Teil ist ringspezifisch | Kanalzuordnung ist eine Abbildung `Slot → Kanal`, nicht fest an Azimut gebunden |

## Ausdrücklich **nicht** zurückgestellt

- **MIDI-Controller.** Ist vorhanden (Keyboard und Pads) und fällt fast von selbst
  ab, sobald es die Modulationsmatrix gibt: Ein Regler am Controller ist eine
  Modulationsquelle wie jede andere, ein Pad ein Trigger wie jeder andere. Sollte
  von Anfang an mitgedacht, wenn auch nicht sofort gebaut werden.
