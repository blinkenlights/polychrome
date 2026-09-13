# Pixie auf dem Raspberry Pi

Ersatz für die ESP32-Firmware in einem Miniaturaufbau: ein Raspberry Pi 4B
treibt CJMCU-8×8-WS2812-Panels über `rpi_ws281x` an und empfängt die Frames
von Octopus per UDP — gleiche Pakete, gleiche Ports, gleiches Protokoll wie
bei den Blinkenled-Platinen.

`pixie_receiver.py` ist das Gegenstück zu `handle_packet()` in
[`blinkenleds/src/Display.cpp`](../blinkenleds/src/Display.cpp). Es dekodiert
`Packet` aus [`protobuf/schema.proto`](../protobuf/schema.proto), schneidet
den Frame nach Panel-Index auf und schiebt die Pixel auf den Streifen.
Bewusst nicht portiert: `WFrame` (die Panels haben keinen Weißkanal) sowie
Easing und Farbkalibrierung aus `Pixel.cpp`.

## Dateien

| Datei | Zweck |
|---|---|
| `01_single_pixel.py` | Minimaltest: Pixel 0 rot. Prüft Verkabelung, PWM/DMA-Zugriff und Farbreihenfolge |
| `02_mapping.py` | Verdrahtung des Panels ermitteln — Modi `walk`, `bands`, `markers` |
| `03_power_test.py` | Stromaufnahme messen — statische Lastzustände, Schritt für Schritt |
| `pixie_receiver.py` | der Empfänger |
| `test_send_frame.py` | Testframes ohne Octopus, exakt so kodiert wie Octopus sie schickt |
| `pixie-receiver.service` | systemd-Unit |

## Zugang

```bash
ssh pixie
```

Der Alias steht in `~/.ssh/config` und zeigt auf `blinkenleds-prototype.local`,
Benutzer `michi`, Key `~/.ssh/pixie`. Der Pi trägt also bereits den Hostnamen,
unter dem Octopus den Pixie-Controller sucht.

## Hardware

- Raspberry Pi 4B
- CJMCU 8×8 WS2812-Panel, Daten an **GPIO 18** (PWM-Kanal 0)
- gemeinsame Masse zwischen Pi und Panel

`rpi_ws281x` greift über `/dev/mem` direkt auf PWM und DMA zu — alles, was
LEDs ansteuert, läuft deshalb als root.

### Stromversorgung

`MAX_BRIGHTNESS = 30` (von 255) ist eine Sicherheitsgrenze, keine
Geschmacksfrage: 64 LEDs auf Vollweiß ziehen bei 255 rund 3,8 A. Das reißt
der 5V-Pin des Pi nicht. Höhere Werte erst mit externem Netzteil — dann
Netzteil und Pi auf gemeinsame Masse legen.

### PWM belegt den Analogaudio-Ausgang

GPIO 18 hängt an PWM-Kanal 0, den sich der Pi sonst mit dem Onboard-Audio
teilt. Bei Zuckungen im Bild `dtparam=audio=off` in `/boot/firmware/config.txt`
setzen und neu starten.

## Einrichtung

Virtualenv und Abhängigkeiten:

```bash
python3 -m venv ~/pixie-venv && ~/pixie-venv/bin/pip install rpi_ws281x protobuf
```

Protobuf-Bindings erzeugen. Sie liegen absichtlich nicht im Repo — die
generierte Datei gehört zur installierten Runtime-Version, nicht zum
Quellcode. `schema.proto` importiert `nanopb.proto`, deshalb beide erzeugen;
sie müssen neben `pixie_receiver.py` liegen:

```bash
sudo apt install -y protobuf-compiler
```

```bash
protoc -I ~/polychrome/protobuf --python_out=$HOME/pixie-pi ~/polychrome/protobuf/schema.proto ~/polychrome/protobuf/nanopb.proto
```

Scheitert der Import später mit *"Descriptors cannot not be created
directly"*, passen `protoc` und das Python-Paket `protobuf` nicht zusammen —
dann `~/pixie-venv/bin/pip install "protobuf<5"` oder die `_pb2.py` mit einem
neueren protoc erzeugen.

## Bring-up

In dieser Reihenfolge, jeder Schritt schließt eine Fehlerquelle aus.

**1. Leuchtet überhaupt etwas?**

```bash
sudo ~/pixie-venv/bin/python ~/pixie-pi/01_single_pixel.py
```

Pixel 0 muss rot leuchten. Leuchtet es grün, ist die Byte-Reihenfolge falsch:
`LED_STRIP` im Skript auf `ws.WS2811_STRIP_RGB` stellen.

**2. Wie liegt die Kette auf dem Raster?**

```bash
sudo ~/pixie-venv/bin/python ~/pixie-pi/02_mapping.py --mode markers
```

Vier Pixel mit eindeutigen Farben (LED 0 rot, 7 grün, 8 blau, 63 weiß); daraus
lässt sich die Verdrahtung vollständig ablesen. `--mode bands` zeigt acht
Farbbänder auf einmal, `--mode walk` läuft die Kette Pixel für Pixel ab.

Der Empfänger nimmt an, dass die CJMCU-Boards **progressiv zeilenweise ab
oben links** verdrahtet sind. Liegt bei dir etwas anderes vor, muss
`build_led_map()` angepasst werden.

**3. Empfänger starten**

```bash
sudo ~/pixie-venv/bin/python ~/pixie-pi/pixie_receiver.py --verbose
```

Er lauscht auf UDP 1337 und loggt alle fünf Sekunden Pakete/s und Frames/s.
`--port` und `--brightness` überschreiben die Defaults.

**4. Ohne Octopus gegentesten**, in einer zweiten Shell auf dem Pi:

```bash
~/pixie-venv/bin/python ~/pixie-pi/test_send_frame.py --pattern corner
```

Erwartet: Ecke oben links weiß, obere Zeile rot, linke Spalte blau. Steht Rot
senkrecht oder Blau waagerecht, ist das Bild gedreht — dann stimmt das
Mapping nicht. `--pixel X Y` setzt stattdessen ein einzelnes Layout-Pixel,
`0 0` ist oben links.

## Stromaufnahme messen

Der Verbrauch skaliert mit Helligkeit **und** mit der Zahl leuchtender
Kanäle: Weiß zieht ungefähr das Dreifache einer einzelnen Farbe, weil alle
drei Chips im WS2812 an sind. Interessant sind deshalb zwei Zahlen — der
Ruhestrom (alle LEDs aus, aber versorgt; die Controller-Chips ziehen jeweils
knapp ein Milliampere) und der Worst Case, alle 64 auf Weiß.

**Anschluss.** Das Multimeter misst Strom in **Reihe**, nicht parallel: die
5V-Leitung zwischen Netzteil und Panel auftrennen und das Messgerät in die
Lücke hängen. Nie die Messstrippen bei eingestelltem Strombereich über die
Versorgung legen — das ist ein Kurzschluss über den Shunt.

**Am VC270**: rote Leitung in die Buchse **10A MAX**, schwarze in **COM**,
Drehschalter auf **10A**, mit **SELECT** auf **DC** stellen (im Display muss
`DC` stehen, nicht `AC`). Zeigt die Anzeige unter etwa 0,35 A, lohnt der
Wechsel auf den feineren Bereich: rote Leitung umstecken in **mA µA**,
Schalter auf **mA**, wieder DC. Der ist auf 400 mA begrenzt (selbst
rücksetzende Sicherung) — bei Vollweiß also zurück auf 10A.

**Messen.** Animationen springen zu schnell für ein Multimeter, deshalb fährt
`03_power_test.py` statische Zustände an und wartet auf Enter:

```bash
sudo ~/pixie-venv/bin/python ~/pixie-pi/03_power_test.py
```

Es geht die Muster von „aus" über einzelne Pixel bis „alle weiß" durch,
jeweils für die Helligkeitsstufen 10, 20 und 30. Der abgelesene Wert lässt
sich eintippen, am Ende steht die Tabelle. `--levels 30` misst nur eine
Stufe, `--hold white --brightness 30` hält ein Muster zum Ruhigmessen.

Stufen über 30 verweigert das Skript ohne `--unsafe` — siehe
[Stromversorgung](#stromversorgung).

## Octopus anbinden

Auf dem Rechner, der Octopus fährt:

```bash
INSTALLATION_MODULE=Octopus.Installation.Pixie mix phx.server
```

Dann auf `localhost:4000` eine App starten, etwa **Pixie Debug**.
`send_in_dev: true` steht in
[`pixie.ex`](../octopus/lib/octopus/installation/pixie.ex), im Dev-Modus wird
also wirklich gesendet.

### Der Pi muss unter dem richtigen Namen erreichbar sein

Pixie läuft im Netzmodus `:individual`, Octopus schickt also **Unicast an
einen Hostnamen** — kein Broadcast. Der Name kommt aus dem Controller-Katalog
und ist für `:pixie` weiterhin `blinkenleds-prototype.local`
([`controllers.ex`](../octopus/lib/octopus/hardware/controllers.ex)), der Name
der ESP32-Platine.

Der Pi heißt bereits so — deshalb funktioniert `ssh pixie` — und antwortet
unter dem Namen per mDNS. Steht der ESP32-Prototyp gleichzeitig im Netz,
streiten sich beide um den Namen; dann eine der beiden Kisten umbenennen.
Löst der Name nicht auf, loggt Octopus

```
Could not resolve hostname: blinkenleds-prototype.local. Using localhost.
```

und schickt alles an 127.0.0.1 — der Pi bleibt dunkel, ohne dass ein Fehler
auffällt. Alternativ die Hostname-Zeile in `controllers.ex` lokal auf den
Pi-Namen oder die IP ändern.

**Ethernet ist nicht nötig.** Unicast an einen Hostnamen läuft über WLAN
genauso; nötig ist nur, dass Pi und Octopus-Rechner im selben Subnetz hängen,
damit `.local` per mDNS auflöst — kein Gastnetz mit Client-Isolation. Das
LED-Timing hängt an DMA und PWM des Pi, nicht am Netz.

### Ports

Der `:pixie`-Controller hat zwei Busse. Port 1 → UDP 1337, Port 2 → UDP 1338.
`Octopus.Installation.Pixie2` und `Octopus.Installation.Woodstock` liegen auf
dem zweiten Bus; für die dann eine zweite Empfänger-Instanz mit
`--port 1338` starten.

## Als Dienst

`pixie-receiver.service` erwartet das Repo unter `/home/michi/pixie-pi` und
das venv unter `/home/michi/pixie-venv`. Bei anderem Benutzernamen beide
Pfade in der Unit anpassen.

```bash
sudo cp ~/pixie-pi/pixie-receiver.service /etc/systemd/system/ && sudo systemctl enable --now pixie-receiver
```

```bash
journalctl -u pixie-receiver -f
```

## Ausbau auf mehrere Panels

Am Kopf von `pixie_receiver.py` stehen zwei Listen, `CHAINS` und `PANELS`.
Zwölf Panels an zwei Ketten sind eine reine Konfigurationsänderung; die
auskommentierte Variante steht direkt darunter. Zwei Ketten brauchen
**unterschiedliche DMA-Kanäle** (10 und 11 sind frei), sonst greifen sich die
beiden `PixelStrip`-Instanzen gegenseitig an. Die zweite Kette läuft über
GPIO 13 auf PWM-Kanal 1.

`frame_index` ist die 1-basierte Position im Frame — dasselbe wie
`PANEL_INDEX` in der ESP32-Firmware und `firmware_panel_index` in
`controllers.ex`. Sie bestimmt, welchen 64-Pixel-Ausschnitt ein Panel aus dem
Paket schneidet. `position` ist die Position innerhalb der Kette und ergibt
den LED-Offset.

## Zwei Fallstricke, die Zeit gekostet haben

**Octopus schickt `rgb_frame_part1`, nicht `rgb_frame`.** `Mixer.handle_frame/2`
schickt jeden RGB-Frame durch `Protobuf.split_and_encode/1`, dessen zweite
Klausel selbst einen 192-Byte-Einzelpanel-Frame als Teil 1 verpackt. Ein
Empfänger, der nur `rgb_frame` behandelt, bleibt dunkel.

**Die Daten kommen nicht in Bildschirmreihenfolge an.** `untangle.ex` legt vor
dem Senden zwei Permutationen hintereinander: das Panel-Wiring
(`:serpentine_vertical_bottom_left`, so hängen die Polychrome-Panels) und die
Firmware-Map, weil der Empfänger normalerweise `map_index()` aus `Display.cpp`
anwendet. Beide Annahmen treffen auf die CJMCU-Boards nicht zu, also dreht
`build_led_map()` beide zurück — danach ist Layout-Index gleich LED-Position.

## Fehlersuche

| Symptom | Ursache |
|---|---|
| `ModuleNotFoundError: schema_pb2` | Bindings nicht erzeugt oder nicht neben `pixie_receiver.py` |
| Empfänger zählt 0 Pakete/s | Octopus schickt woanders hin — Hostname-Auflösung prüfen, siehe oben |
| Pakete kommen an, Panel bleibt dunkel | `--brightness` zu niedrig, oder Luminanz aus der `FirmwareConfig` auf 0 |
| Bild gedreht oder gespiegelt | Mapping — mit `test_send_frame.py --pattern corner` gegentesten |
| `Paket nicht dekodierbar` | `_pb2.py` passt nicht zur aktuellen `schema.proto` |
| Zucken, flackernde Pixel | Onboard-Audio belegt PWM: `dtparam=audio=off` |
