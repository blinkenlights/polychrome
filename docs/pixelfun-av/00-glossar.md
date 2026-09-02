# 00 — Glossar

Alles, was in den anderen Dokumenten vorausgesetzt wird — für Leute, die nicht aus
der Audiowelt kommen.

## Was wir schon haben

### beak

`beak` ist ein **eigenes kleines Programm** im Repo (Ordner `beak/`), geschrieben in
C++ von Lukas Güldenstein, seit Mai 2023. Es ist **kein Elixir** und läuft als
separater Prozess neben Octopus — oft auf demselben Rechner.

Seine einzige Aufgabe: **Töne aus der Soundkarte holen**. Octopus selbst kann keinen
Ton machen; die BEAM (die Erlang-VM) ist gut im Verwalten und Vernetzen, aber sie
rechnet keine Audiosignale. Also schickt Octopus kleine Nachrichten übers Netz
(„spiel Datei X auf Kanal 3", „spiel Note C4 auf Kanal 7") und beak setzt das in
Klang um.

Es kann genau zwei Dinge:

1. **Samples abspielen** — eine `.wav`-Datei auf einem bestimmten Ausgabekanal.
   Nachricht: `AudioFrame{uri, channel, stop}`.
2. **Töne synthetisieren** — ein einfacher eingebauter Synthesizer mit Wellenform,
   Hüllkurve, Filter und Hall. Nachricht: `SynthFrame{NOTE_ON/NOTE_OFF, channel,
   note, velocity, …}` — im Prinzip wie ein MIDI-Keyboard, nur über Netzwerk.

Wichtig für uns: **beak hat einen Ausgabekanal pro Panel.** In Mildenberg stand
hinter jedem Fenster ein Lautsprecher. Kanal 1 = Panel 1, Kanal 2 = Panel 2, usw.

Benutzt wird beak heute von den Apps `encounter`, `senso`, `lemmings`,
`space_invaders`, `rickroll`, `text` und `beak_test` — meistens für Soundeffekte
(Spielgeräusche, Sprache, Melodien).

**JUCE** ist nur das C++-Framework, mit dem beak gebaut ist — ein Standardbaukasten
für Audio-Software. Nicht weiter wichtig, außer: wer beak erweitern will, muss C++
schreiben und neu kompilieren.

### analyzer

Noch ein kleines C++-Programm im Repo (`analyzer/`), ebenfalls JUCE. Es **hört zu**
statt zu spielen: Es nimmt ein Audiosignal entgegen, teilt es in drei
Frequenzbereiche — **bass / mid / high** (tief / mittig / hoch) — misst, wie laut
jeder Bereich gerade ist, und schickt diese drei Zahlen ~60-mal pro Sekunde an
Octopus.

- **RMS** heißt nur „gemittelte Lautstärke über ein kurzes Zeitfenster". Eine Zahl
  pro Bereich, die sagt: wie viel Energie steckt gerade im Bass.
- **3-Band** = drei solche Zahlen.

In Octopus kommen sie als `SoundToLightControlEvent{bass, mid, high}` an und landen
in Pixelfun als die Formelvariablen **`l`, `m`, `h`** (low/mid/high). Man kann also
schon heute `sin(x + t) * l` schreiben, und das Muster pumpt im Bass.

### Warum gibt es das schon?

Weil die Installation 2023 in Mildenberg **von Anfang an Ton hatte**. Es gab
Spiele-Apps mit Soundeffekten (deshalb beak) und eine Sound-zu-Licht-Reaktion für
Musik von außen (deshalb der analyzer). Was es nie gab, ist ein **Werkzeug zum
Komponieren** — Ton war immer ein Anhängsel einzelner Apps, nie etwas, das man
gestaltet.

Der aktuelle Stand in einem Satz:

- **Sound → Licht** gibt es, aber sehr grob: drei Lautstärkezahlen von außen.
- **Licht → Sound** gibt es, aber fest verdrahtet: Apps rufen im Code „spiel diesen
  Sound" auf.
- **Eine gemeinsame Zeitachse, ein Raumkonzept, eine Oberfläche** gibt es nicht.

## Audio-Grundbegriffe

**Sample** — eine aufgenommene Audiodatei (`.wav`). „Ein Sample abspielen" heißt:
Datei von vorn abspielen. Man kann sie schneller/langsamer abspielen (ändert
gleichzeitig die Tonhöhe), an einer beliebigen Stelle starten, rückwärts, usw.

**Synthese** — Klang wird gerechnet statt abgespielt. Ein Oszillator erzeugt eine
Schwingung (Sinus, Sägezahn, Rauschen), ein Filter nimmt Frequenzen weg, eine
Hüllkurve formt die Lautstärke über die Zeit.

**Hüllkurve (Envelope, ADSR)** — beschreibt, wie sich die Lautstärke eines einzelnen
Tons über die Zeit entwickelt. Vier Zahlen:

| | | |
|---|---|---|
| **A**ttack | Anstieg | Wie lange bis zum lautesten Punkt? Kurz = perkussiv (Klick, Snare). Lang = anschwellend (Streicher, Pad). |
| **D**ecay | Abfall | Wie schnell fällt es danach ab? |
| **S**ustain | Halten | Auf welchem Pegel bleibt es, solange die Taste gedrückt ist? |
| **R**elease | Ausklang | Wie lange klingt es nach dem Loslassen aus? |

Ein Klavierton: kurzes Attack, langes Decay, kein Sustain. Ein Drone: langes Attack,
volles Sustain, langes Release. Hüllkurven gibt es auch für andere Dinge als
Lautstärke — z. B. eine Filter-Hüllkurve, die den Klang beim Anschlag kurz öffnet.

**Granular** — eine Technik, bei der ein Sample nicht am Stück abgespielt wird,
sondern in Hunderten winziger Schnipsel („Körner", je 10–100 ms), die überlappend
und in variabler Reihenfolge/Tonhöhe abgefeuert werden. Ergebnis: aus einer
Sekunde Aufnahme wird eine beliebig lange, schwebende Klangwolke. Das ist das
Standardmittel für Ambient-Flächen, die nie exakt loopen.

**Drone** — ein liegender, langsam sich verändernder Dauerklang. Kein Rhythmus,
keine Melodie, eher Atmosphäre.

**Gain-Staging** — dafür sorgen, dass an jeder Stelle der Kette (Einzelstimme →
Summe → Ausgang) der Pegel in einem sinnvollen Bereich liegt: laut genug für
Rauschabstand, leise genug, dass nichts übersteuert. Praktisch: Einzelslots leiser,
Summe kontrolliert.

**Limiter** — ein Sicherheitsnetz ganz am Ende: verhindert hart, dass das Signal
über eine Grenze geht. Ohne Limiter kann eine Formel, die versehentlich zwölf
Stimmen gleichzeitig auf voll dreht, sehr unangenehm laut werden.

**Panic** — ein Knopf, der alles sofort verstummen lässt: alle Klänge abbrechen,
alle Kanäle stumm. Braucht jedes Instrument, das programmierbar ist, weil ein Fehler
in einer Regel sonst einen Dauerton produziert, den man nicht mehr los wird.

**Bus** — ein Sammelweg, über den mehrere Signale zusammenlaufen oder verteilt
werden. „Master-Bus" = die Summe von allem. „Cue-Bus" = ein extra Ausgang zum
Vorhören über Kopfhörer.

## SuperCollider-Begriffe

**SuperCollider (SC)** — eine seit ~1996 gepflegte Umgebung für Klangsynthese, in
Installationen und Live-Coding sehr verbreitet. Für uns interessant ist nur der
Server-Teil, **`scsynth`**: ein Programm, das Klang rechnet und Befehle über das
Netzwerk entgegennimmt (per OSC, s. u.). Man muss die SuperCollider-Sprache
(`sclang`) **nicht** benutzen — Elixir kann `scsynth` direkt steuern.

**SynthDef** — eine „Bauanleitung für einen Klang", die man einmal definiert und
dann beliebig oft startet. Etwa: „Sägezahn → Tiefpassfilter → Hüllkurve → Ausgang
auf Kanal n". Vergleichbar mit einem Preset auf einem Synthesizer.

**Buffer** — ein Stück Speicher im Klangserver, in dem eine Audiodatei liegt. Bevor
man ein Sample abspielen kann, muss die Datei einmal in einen Buffer geladen werden
(`/b_allocRead` ist einfach der Befehl „lade Datei X in Speicherplatz Nr. 4"). Danach
kann man sie ohne Festplattenzugriff sofort und beliebig oft abspielen — auch
rückwärts, mit anderer Geschwindigkeit oder granular.

**OSC (Open Sound Control)** — ein sehr einfaches Netzwerkprotokoll für
Musiksoftware. Eine Nachricht ist eine Adresse plus ein paar Zahlen, z. B.
`/s_new "pluck" 1003 0 0 "freq" 440`. Octopus benutzt OSC bereits (Port 8000) zum
Empfangen von Parametern.

**Timetag** — eine Zeitangabe, die man an eine OSC-Nachricht anhängen kann: „führe
das exakt zu diesem Zeitpunkt aus". `scsynth` kann Befehle so **sample-genau in der
Zukunft** planen. Das ist der Grund, warum Timing mit SC gut wird und mit beak nicht:
beak spielt, sobald das Paket ankommt — mit allem Netzwerk- und Scheduler-Zittern.

**xrun** — ein Aussetzer: Der Rechner war kurz zu langsam, der Audiopuffer lief leer,
man hört ein Knacken. Der übliche Betriebsärger bei Audio auf kleinen Rechnern.

**systemd-Dienst** — der Standardmechanismus unter Linux, ein Programm beim Booten
automatisch zu starten und bei Absturz neu zu starten. Wenn `scsynth` auf dem Pi
läuft, sollte es als solcher Dienst laufen, damit nach einem Stromausfall alles von
allein wiederkommt.

## Sequencer-Begriffe

**Transport** — der zentrale „Bandmaschinen-Kopf": Play/Stop, Tempo, aktuelle
Position. Alles, was im Takt laufen soll, fragt den Transport nach der Zeit.

**BPM** — Beats per minute, das Tempo. 120 BPM = zwei Schläge pro Sekunde.

**Takt / Beat / Step** — ein Takt (Bar) besteht typischerweise aus 4 Beats, ein Beat
wird für die Bedienung meist in 4 Steps unterteilt → 16 Steps pro Takt. Das ist das
Raster, in dem ein Step-Grid arbeitet.

**Step-Grid** — das Raster aus Drumcomputern: Zeilen sind Klänge, Spalten sind die
16 Steps eines Takts. Wo ein Kästchen an ist, klingt es. Damit macht man Rhythmus.

**Modulation** — etwas verändert kontinuierlich etwas anderes: ein langsam
schwingender Wert schiebt den Filter auf und zu, oder die Helligkeit des Bildes.
Nicht „an/aus", sondern „mehr/weniger".

**LFO** — Low Frequency Oscillator: eine langsame Schwingung (z. B. eine Sinuswelle
alle 8 Takte), die man als Modulationsquelle benutzt.

**Polymeter** — mehrere Muster mit **unterschiedlicher Länge** laufen gleichzeitig
(z. B. eines über 16 Steps, eines über 12). Sie geraten gegeneinander in
Verschiebung und wiederholen sich erst nach vielen Takten wieder gleich. Sehr
nützlich für stundenlangen Betrieb.

**Look-ahead** — der Trick, mit dem Sequencer sauber im Takt bleiben: Ereignisse
werden nicht in dem Moment losgeschickt, in dem sie klingen sollen, sondern
z. B. 200 ms vorher mit der Anweisung „spiele das exakt um 20:14:03,250".

**Quantisierung** — Ereignisse auf ein Raster zwingen (der nächste Takt, der nächste
Beat). Wichtig für Übergänge: ein Wechsel klingt richtig, wenn er auf der Eins passiert.

## Die drei Wörter, die in diesem Projekt eine Sonderbedeutung haben

**Probe** (Messstelle, nicht „Übung") — ein fester Punkt auf dem Ring, an dem wir die
Pixelfun-Formel zusätzlich auswerten. Die Formel liefert für jeden Ort und jeden
Moment eine Zahl zwischen −1 und +1; für das Bild wird sie an jedem Pixel
ausgewertet, für den Klang nur an ein paar wenigen Stellen — voreingestellt an den
zwölf Panelmitten. Diese zwölf Zahlen sind unser Abgriff: „wie hell ist die Formel
gerade bei Panel 7?" Daraus wird entweder ein kontinuierlicher Steuerwert (Lautstärke
einer Stimme) oder ein Auslöser (immer wenn der Wert eine Schwelle übersteigt:
Ton spielen). Bildlich: zwölf Tonabnehmer, in das Lichtfeld gehängt.

*Wie* ein Panel zu einer Zahl wird, ist im Studio unter „Quellen" einstellbar und
gilt für die ganze Wand — ein Panel ist ja 8×8 Pixel groß, und eine Welle läuft
darüber hinweg statt auf einem Punkt zu landen:

- **Mittelpixel** — ein Pixel in der Mitte. Am schärfsten, kostet zwölf
  Auswertungen pro Frame.
- **Panelmittel** — Mittelwert mit Vorzeichen. Ruhiger; hebt sich genau dort auf,
  wo eine Farbnaht durch das Panel läuft.
- **Panelhelligkeit** — mittlere Helligkeit, immer positiv. Am nächsten an dem,
  was man sieht.
- **Panelmaximum** — der stärkste Pixel. Reagiert, sobald *irgendwo* etwas hell
  wird.

Die drei panelweiten Modi werten alle 768 Pixel aus und kosten gemessen 0,23 ms
pro Frame von 33 ms — die Wahl ist also eine musikalische, keine technische.

**Slot** — eine Klangquelle mit ihrer Ring-Zuordnung. Statt „Spur" wie in einer DAW,
weil hier zu jedem Klang gehört, *wo* auf dem Ring er erklingt.

**Komposition** — der komplette speicherbare Zustand: Szene (Pixelfun-Formel und
-Parameter) + Klang-Slots + Pattern + Kopplungen + Tempo. Das ist die Einheit, die
später in der Rotation der Installation läuft.
