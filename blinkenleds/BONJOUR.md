# Blinkenleds Bonjour / mDNS service discovery

Each LED bus is announced as a separate `_blinkenleds._udp` service on the shared device hostname.

## Service

| Field | Value |
|-------|--------|
| Service type | `_blinkenleds._udp` |
| Device hostname | `blinkenleds-N` / `blinkenleds-prototype` (OTA) |
| Instance name (single-port) | `Polychrome port 1` |
| Instance name (dual-port / Pixie) | `Pixie port 1`, `Pixie port 2` |
| Port | `1337 + (bus index)` — bus 0 → 1337, bus 1 → 1338 |

## TXT records (`txt_version=1`)

| Key | Example | Meaning |
|-----|---------|---------|
| `txt_version` | `1` | Schema version |
| `mac` | `54:43:b2:b6:6e:57` | Device Ethernet MAC |
| `bus` | `0` | 0-based bus index on the device |
| `panel_index` | `1` | Firmware broadcast slice index (`PANEL_INDEX`) |
| `matrix` | `8x8` | Firmware strip topology (not installation layout) |
| `wire_map` | `serpentine_horizontal_bottom_left` | Firmware `map_index` wiring |
| `max_px` | `64` | Addressable pixels per bus |
| `fw` | version string | Firmware version |

Dynamic runtime state (`config_phash`, FPS, reply port) is **not** in TXT; it is carried in periodic `FirmwareInfo` UDP packets back to the learned sender.

## Browse (examples)

```bash
dns-sd -B _blinkenleds._udp
# or
avahi-browse -r _blinkenleds._udp
```
