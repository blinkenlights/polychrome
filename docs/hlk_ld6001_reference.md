# HLK-LD6001A-60G Human Tracking Radar — Developer Documentation

Version basis: HLK-LD6001A-60G Human Trajectory Radar Sensor Module Manual V1.1 (modified 2024-05-11)

---

## 1. Purpose and scope

This document is a developer-oriented rewrite of the vendor manual for the **HLK-LD6001A-60G** human tracking radar module. It is intended to serve as a practical reference for firmware and embedded developers, host-side parser implementations, AI coding agents generating integrations, and engineers configuring or validating deployments.

The focus is on:
- electrical and installation requirements,
- UART command interface,
- initialization flow,
- binary protocol structure,
- byte-accurate parsing of tracking output,
- interpretation of the device coordinate system and configuration parameters.

Where the original manual is terse or awkwardly formatted, this document makes the implied behavior explicit.

---

## 2. Device overview

The HLK-LD6001A-60G is a **60–64 GHz indoor mmWave radar sensor** designed for **human trajectory tracking**.

### Main capabilities

- Multi-target tracking, up to **10 people**
- Real-time position reporting
- Motion trajectory tracking
- Detection of micro-motion and static humans
- Indoor operation largely unaffected by:
  - lighting,
  - humidity,
  - dust,
  - noise,
  - ordinary optical occlusion

### Claimed strengths

The vendor specifically states that the module is designed to suppress false detections caused by:
- curtains,
- green plants,
- multipath effects.

### Installation model

This module is intended for **ceiling installation**, with the antenna facing downward.

---

## 3. Key specifications

| Item | Value |
|---|---|
| Installation style | Top / ceiling installation |
| Detection distance | 0.5 m to 8 m |
| Effective projected ground coverage | Circular area; vendor also references a 3.5 m radius case at 2.7 m height |
| Angular coverage | ±60° azimuth and pitch |
| Supply voltage | 3.3 V |
| Communication | TTL serial |
| Operating frequency | 60–64 GHz |
| Processing cycle | ≤ 30 ms |
| Average power | 0.3 W |
| Peak power | 1.7 W |
| Module size | 29.36 mm × 28 mm |

### Detection-distance caveat

The manual explicitly notes that actual performance depends on:
- installation environment,
- target body size,
- target angle relative to the radar,
- movement amplitude.

Treat the quoted distance figures as indicative, not guaranteed.

---

## 4. Mechanical and deployment guidance

### 4.1 Intended installation position

The module should be mounted:
- on the ceiling,
- with the antenna facing downward,
- at a height of **2.5 m to 3.0 m**.

### 4.2 Environment constraints

The vendor recommends:
- fixing the module rigidly to avoid vibration or shaking,
- keeping the surrounding environment as open as possible,
- securing the USB/serial cable so cable movement does not introduce interference.

This implies that mechanical instability may degrade tracking quality.

### 4.3 Detection zone concept

The detection zone is defined by a combination of:
- a **radial limit** (`AT+RANGE`),
- rectangular coordinate bounds:
  - `AT+XPosiD`
  - `AT+XNegaD`
  - `AT+YPosiD`
  - `AT+YNegaD`

The target must lie within the radial range and within the configured X/Y boundaries. The accepted region is the intersection of the projected circular detection range and the configured X/Y boundary box.

---

## 5. Electrical interface

### 5.1 Pins

| Pin | Description |
|---|---|
| `3V3` | Module power supply input |
| `NRST` | Module reset |
| `TX` | UART transmit from module |
| `RX` | UART receive to module |
| `GND` | Ground |

### 5.2 Voltage limits

#### Absolute/rated limits

| Signal | Min | Max | Unit |
|---|---:|---:|---|
| `3V3` | -0.5 | 3.6 | V |
| I/O (`TX`, `RX`, `NRST`) | -0.5 | 3.6 | V |

#### Typical operating values

| Signal | Typical value |
|---|---|
| `3V3` | 3.0 V to 3.3 V |
| I/O | -0.5 V to `VDD + 0.3 V` |

The manual defines `VDD` here as the power supply input.

### 5.3 Power consumption and supply design

The module contains RF circuitry and has nontrivial transient current draw.

The vendor states approximately:
- **530 mA** during active transmission periods,
- **80 mA** during standby periods,
- **110 mA average** when operating with a 100 ms processing cycle.

### Power design recommendation

Use a **3.3 V supply capable of at least 1 A output**. This recommendation appears directly motivated by peak current demand, not average current alone.

---

## 6. Host communication model

The module is controlled and read through a **TTL UART**.

### Important points

- Commands are ASCII **AT commands**
- Commands are terminated by **newline** (`\n`)
- The module can operate in multiple output modes selected by `AT+DEBUG=X`
- The full tracking protocol for machine parsing is available in **`AT+DEBUG=3`**
- The default serial baud rate is stated as **921600**
- The vendor host-computer screenshot for `DEBUG=2` shows **115200**, so do not assume all tools and modes use the same speed without verification

### Recommended implementation stance

For your own integration:
1. assume the module command interface is UART-based,
2. start with the documented default baud of **921600**,
3. support reconfiguration via `AT+BAUD=XX`,
4. treat any vendor-tool-specific baud as tool behavior, not necessarily the module default in all situations.

---

## 7. Operational modes

The `AT+DEBUG` parameter selects what the module outputs.

| Command | Meaning |
|---|---|
| `AT+DEBUG=0` | Protocol mode, described by the manual as the default and as a **simple protocol** |
| `AT+DEBUG=1` | String output mode |
| `AT+DEBUG=2` | Debug mode used by the vendor host computer |
| `AT+DEBUG=3` | Protocol mode with **detailed protocol** output |

### Which mode to use?

Use **`AT+DEBUG=3`** for any implementation that needs:
- per-target positions,
- per-target velocities,
- target IDs,
- machine-parsed tracking frames.

Use **`AT+DEBUG=0`** only if you need the minimal people-count frame.

---

## 8. Initialization and runtime sequence

The original manual lists commands but does not clearly explain a minimal real startup flow. The following sequence is the most practical interpretation of the documented behavior.

### 8.1 Recommended startup procedure

1. Apply stable **3.3 V** power.
2. Open the UART at the expected baud rate.
3. Optionally reset the module:
   - `AT+RESET\n`
4. Configure the desired output mode:
   - `AT+DEBUG=3\n` for full binary tracking data
5. Optionally configure geometry and timing parameters.
6. Start operation:
   - `AT+START\n`

### 8.2 Recommended configuration-before-start sequence

A robust initialization sequence for deployed systems is:

```text
AT+STOP\n
AT+READ\n
AT+DEBUG=3\n
AT+HEIGHTD=300\n
AT+RANGE=450\n
AT+XPosiD=450\n
AT+XNegaD=-450\n
AT+YPosiD=450\n
AT+YNegaD=-450\n
AT+Moving=110\n
AT+Static=100\n
AT+Exit=5\n
AT+START\n
```

This is not explicitly given by the vendor as a required sequence, but it is a sensible derived sequence from the documented command set and defaults.

### 8.3 Command acknowledgement

The manual states:
- success response: **`AT+OK`**
- failure response: **`Save Para Fail`**

If configuration fails, the manual says the command should be sent again.

### Practical implication

Your host software should:
- read and parse command responses,
- retry writes when `Save Para Fail` is received,
- avoid assuming that a transmitted setting was stored unless acknowledged.

---

## 9. Command reference

All commands below are documented with a trailing newline.

### 9.1 Control commands

| Command | Meaning |
|---|---|
| `AT+START\n` | Start-up / start running |
| `AT+STOP\n` | Stop |
| `AT+RESET\n` | Reset |
| `AT+READ\n` | Read parameters |
| `AT+RESTORE\n` | Restore default settings |

### 9.2 General serial/output configuration

| Command | Meaning |
|---|---|
| `AT+BAUD=XX\n` | Configure serial baud rate; documented default is `921600` |
| `AT+HEATIME=XX\n` | Heartbeat interval for protocol output, unit seconds, range `10..999`, default `60` |
| `AT+DEBUG=X\n` | Output/protocol mode selector |

#### `AT+DEBUG=X` values

| Value | Meaning |
|---:|---|
| `0` | Simple protocol mode |
| `1` | String output |
| `2` | Vendor host-computer debug mode |
| `3` | Detailed protocol mode |

### 9.3 Detection-zone configuration

| Command | Meaning |
|---|---|
| `AT+RANGE=XX\n` | Projected ground detection radius in cm; range `10..500`; default `450` |
| `AT+HEIGHTD=XXX\n` | Vertical distance / installation height in cm; range `50..500`; default `300` |
| `AT+XPosiD=XXX\n` | Positive X range in cm; range `20..500`; default `450` |
| `AT+XNegaD=-XXX\n` | Negative X range in cm; range `-500..-20`; default `-450` |
| `AT+YPosiD=XXX\n` | Positive Y range in cm; range `20..500`; default `450` |
| `AT+YNegaD=-XXX\n` | Negative Y range in cm; range `-500..-20`; default `-450` |

### 9.4 Target disappearance timing

| Command | Meaning |
|---|---|
| `AT+Moving=XXX\n` | Moving-target disappearance time in units of 100 ms; range `5..1000`; default `110` |
| `AT+Static=XXX\n` | Static-target disappearance time in units of 100 ms; range `5..1000`; default `100` |
| `AT+Exit=XXX\n` | Exit-boundary time in units of 100 ms; range `2..1000`; default `5` |

### Interpreting timing values

Because these parameters are specified in **100 ms units**:
- `AT+Moving=110` = 11.0 s
- `AT+Static=100` = 10.0 s
- `AT+Exit=5` = 0.5 s

These values appear to control how long tracks remain before being dropped under different conditions.

---

## 10. Coordinate system and physical meaning

The manual defines the coordinates as:
- **X** = left/right
- **Y** = front/back
- **Z** = height

The page-8 diagram shows the module with axes laid out on the board image. In practical terms:
- X is the lateral axis in the ceiling plane,
- Y is the other horizontal axis in the ceiling plane,
- Z is vertical.

The detailed protocol section describes `X`, `Y`, `Z` and `Vx`, `Vy`, `Vz` as floating-point values.

### Units

The vendor does not explicitly label the frame payload coordinate units in the protocol section, but the example values and installation context strongly indicate **meters** for position and **meters/second** for velocity. That is also consistent with the sample decoded values:
- X ≈ `-1.17`
- Y ≈ `2.50`
- Z ≈ `0.32`
- velocities near ±`0.1`

The configuration commands, by contrast, use **centimeters**.

### Implementation recommendation

Treat protocol-frame values as:
- `x`, `y`, `z`: `float32`, meters
- `vx`, `vy`, `vz`: `float32`, meters per second

and treat command parameters as centimeters exactly as documented.

---

## 11. Protocol mode `AT+DEBUG=0` — simple protocol

This is the minimal binary protocol. The manual provides a single complete example.

### 11.1 Example packet

```text
55 AA 0A 04 00 00 00 00 00 0E
```

### 11.2 Field interpretation

| Bytes | Meaning |
|---|---|
| `55 AA` | Frame header |
| `0A` | Number of bytes |
| `04` | Type = `0x04`, number-of-people frame |
| `00 00` | Reserved |
| `00 00` | Reserved |
| `00` | Number of people counted |
| `0E` | XOR checksum |

#### Checksum definition

The manual states that the checksum is the XOR of:

```text
0A 04 00 00 00 00 00
```

That means, for this simple mode, the frame header `55 AA` is not included in the XOR.

### 11.3 Practical use

This mode is useful only if all you need is a low-information occupancy count. It does **not** provide per-target positions or velocities.

---

## 12. Detailed protocol `AT+DEBUG=3`

This is the main protocol for integration work.

The manual calls this “demo mode” in one place, but the command table clearly identifies `DEBUG=3` as **detailed protocol mode**. For implementation purposes, this is the structured binary tracking stream.

### 12.1 Overall frame structure

A frame consists of:
1. fixed 8-byte header,
2. total-frame length,
3. frame number,
4. TLV marker 1,
5. point-cloud length,
6. TLV marker 2,
7. tracking-data length,
8. one or more 32-byte personnel records,
9. one-byte XOR checksum.

### 12.2 Field-by-field layout

| Field | Size | Type | Description |
|---|---:|---|---|
| `HEAD` | 8 bytes | fixed bytes | `01 02 03 04 05 06 07 08` |
| `LENGTH` | 4 bytes | `uint32` | total length of the entire frame |
| `FRAME` | 4 bytes | `uint32` | frame number |
| `TLVs` | 4 bytes | `uint32` | value `1` |
| `POINTLENTH` | 4 bytes | `uint32` | point cloud length; always `0` |
| `TLVs` | 4 bytes | `uint32` | value `2` |
| `TRACKLENTH` | 4 bytes | `uint32` | tracking payload length |
| `Personnel[0..n-1]` | `32 * n` bytes | records | per-person records |
| `Check` | 1 byte | XOR | checksum over frame number and personnel info |

#### Manual spelling note

The vendor uses the names:
- `POINTLENTH`
- `TRACKLENTH`

These are obvious misspellings of “length”, but when discussing the vendor format it is useful to recognize them.

### 12.3 Endianness

The sample frame proves that multi-byte values are encoded **little-endian**:
- `40 00 00 00` = 64
- `A3 01 00 00` = 419
- `20 00 00 00` = 32

### Implementation rule

Parse all integer fields as **little-endian unsigned 32-bit integers** unless the field is explicitly described otherwise.

### 12.4 Personnel record structure

Each person occupies **32 bytes**:

| Offset within record | Size | Type | Field | Meaning |
|---:|---:|---|---|---|
| `0` | 4 | `uint32` | `F` | Reserved |
| `4` | 4 | `uint32` | `ID` | Person identifier |
| `8` | 4 | `float32` | `X` | left/right coordinate |
| `12` | 4 | `float32` | `Y` | front/back coordinate |
| `16` | 4 | `float32` | `Z` | height |
| `20` | 4 | `float32` | `Vx` | X velocity |
| `24` | 4 | `float32` | `Vy` | Y velocity |
| `28` | 4 | `float32` | `Vz` | Z velocity |

#### Derived target count

The manual defines:

```text
number_of_people = TRACKLENTH / 32
```

This means the frame does not carry a dedicated target count field in detailed mode; the count is derived from the tracking payload size.

### 12.5 TLV interpretation

The frame contains two TLV markers:
- TLV `1` followed by point-cloud length, always zero
- TLV `2` followed by tracking-data length

The current documentation provides no actual point-cloud payload. In practice:
- you should parse and retain the fields,
- but you should expect the point-cloud section to be empty.

### Practical implication

A parser should not hardcode “data starts at byte 28 because that is always true forever”; instead, it should understand that:
- the point section is currently zero-length,
- the track section is the meaningful payload,
- future firmware could theoretically alter payload content while still using the same overall scheme.

That said, for this documented firmware, byte offset 32 is the start of track records.

---

## 13. Checksum in detailed mode

The checksum is a **one-byte XOR**.

The manual states that it is computed over:
- the **frame number** bytes,
- the **personnel information content**.

It does **not** include:
- the 8-byte header,
- the total length field,
- the TLV marker fields,
- the point length field,
- the track length field,
- the final checksum byte itself.

### 13.1 Exact checksum range

For the documented frame layout, XOR the bytes of:

```text
FRAME (4 bytes) + TRACK_DATA (TRACKLENTH bytes)
```

### 13.2 Practical checksum algorithm

```text
checksum = 0
for each byte in frame_number_bytes:
    checksum ^= byte

for each byte in tracking_payload_bytes:
    checksum ^= byte
```

### Important implementation note

Do not XOR the entire frame body. Only XOR the exact documented checksum domain.

---

## 14. Complete data-packet example from the manual

This section preserves the full vendor example because it is directly useful when validating implementations.

### 14.1 Raw packet bytes

```text
01 02 03 04 05 06 07 08
40 00 00 00
A3 01 00 00
01 00 00 00
00 00 00 00
02 00 00 00
20 00 00 00
00 00 00 00
00 00 00 00
21 28 96 BF
CB 85 20 40
9A AB A3 3E
8A BD C1 3D
50 98 99 BD
40 52 C3 3A
CC
```

As one continuous byte stream:

```text
01 02 03 04 05 06 07 08 40 00 00 00 A3 01 00 00 01 00 00 00 00 00 00 00 02 00 00 00 20 00 00 00 00 00 00 00 00 00 00 00 21 28 96 BF CB 85 20 40 9A AB A3 3E 8A BD C1 3D 50 98 99 BD 40 52 C3 3A CC
```

### 14.2 Decode of each field

| Bytes | Decode |
|---|---|
| `01 02 03 04 05 06 07 08` | fixed frame header |
| `40 00 00 00` | total frame length = `64` bytes |
| `A3 01 00 00` | frame number = `419` |
| `01 00 00 00` | TLV = `1` |
| `00 00 00 00` | point-cloud length = `0` |
| `02 00 00 00` | TLV = `2` |
| `20 00 00 00` | tracking payload length = `32` bytes |
| `00 00 00 00` | reserved field `F` for person 0 |
| `00 00 00 00` | person ID = `0` |
| `21 28 96 BF` | X |
| `CB 85 20 40` | Y |
| `9A AB A3 3E` | Z |
| `8A BD C1 3D` | Vx |
| `50 98 99 BD` | Vy |
| `40 52 C3 3A` | Vz |
| `CC` | checksum |

### 14.3 Float decoding of the sample

Interpreting the six float fields as little-endian IEEE-754 `float32` gives approximately:

| Field | Bytes | Value |
|---|---|---:|
| `X` | `21 28 96 BF` | `-1.1731` |
| `Y` | `CB 85 20 40` | `2.5082` |
| `Z` | `9A AB A3 3E` | `0.3197` |
| `Vx` | `8A BD C1 3D` | `0.0941` |
| `Vy` | `50 98 99 BD` | `-0.0750` |
| `Vz` | `40 52 C3 3A` | `0.0015` |

The original manual gives approximate decoded values around:
- position: `-1.17`, `2.50`, `0.31`
- velocity: `0.094`, `-0.074`, `0.001`

The minor differences are normal rounding differences.

### 14.4 Checksum verification of the sample

The checksum input domain is:
- frame number bytes:
  - `A3 01 00 00`
- plus the 32-byte personnel record:
  - `00 00 00 00 00 00 00 00 21 28 96 BF CB 85 20 40 9A AB A3 3E 8A BD C1 3D 50 98 99 BD 40 52 C3 3A`

XOR of those bytes yields:

```text
CC
```

which matches the packet checksum byte.

---

## 15. Parser design guidance

### 15.1 Streaming behavior

The UART output is a continuous byte stream. A correct parser should therefore be a **stream parser**, not a packet parser that assumes reads are frame-aligned.

### Recommended behavior

- scan for the 8-byte header,
- read the 4-byte total length field,
- wait until the entire frame body is available,
- validate structure,
- validate checksum,
- emit decoded targets.

### 15.2 Frame-size validation

A detailed-mode frame has this minimum structure:
- header: 8 bytes
- length: 4 bytes
- frame number: 4 bytes
- TLV1: 4 bytes
- point length: 4 bytes
- TLV2: 4 bytes
- track length: 4 bytes
- checksum: 1 byte

That is **33 bytes minimum**, even for zero targets.

Because each target record is 32 bytes, valid frame lengths in detailed mode should satisfy:

```text
frame_length = 32 + track_length + 1
```

where:
- the initial 32 bytes are all fields through `TRACKLENTH`,
- the final `1` byte is checksum.

Equivalently:

```text
track_length = frame_length - 33
```

In the sample:
- `frame_length = 64`
- `track_length = 32`

which is consistent.

### Recommended parser checks

Reject or resync on frames where:
- header is wrong,
- `length < 33`,
- `track_length % 32 != 0`,
- `length != 33 + track_length`,
- checksum mismatches.

### 15.3 Resynchronization strategy

If parsing fails:
1. discard bytes until the first plausible start of header,
2. continue scanning for the full header sequence `01 02 03 04 05 06 07 08`,
3. only trust a candidate frame after length and checksum validation.

This is important because binary serial streams can become misaligned after:
- startup mid-frame,
- line noise,
- host buffer loss,
- baud mismatch during development.

---

## 16. Reference binary layout

### 16.1 Detailed-mode frame layout by absolute offset

| Absolute offset | Size | Type | Field |
|---:|---:|---|---|
| `0` | 8 | bytes | header |
| `8` | 4 | `uint32` | total length |
| `12` | 4 | `uint32` | frame number |
| `16` | 4 | `uint32` | TLV1 (= 1) |
| `20` | 4 | `uint32` | point length (= 0) |
| `24` | 4 | `uint32` | TLV2 (= 2) |
| `28` | 4 | `uint32` | track length |
| `32` | `track_length` | bytes | target records |
| `32 + track_length` | 1 | byte | checksum |

### 16.2 Target record layout by relative offset

| Relative offset | Size | Type | Field |
|---:|---:|---|---|
| `0` | 4 | `uint32` | reserved |
| `4` | 4 | `uint32` | target ID |
| `8` | 4 | `float32` | X |
| `12` | 4 | `float32` | Y |
| `16` | 4 | `float32` | Z |
| `20` | 4 | `float32` | Vx |
| `24` | 4 | `float32` | Vy |
| `28` | 4 | `float32` | Vz |

---

## 17. Reference parsing pseudocode

### 17.1 Frame parser pseudocode

```python
HEADER = bytes([1, 2, 3, 4, 5, 6, 7, 8])

def xor_bytes(data: bytes) -> int:
    x = 0
    for b in data:
        x ^= b
    return x

def parse_u32le(b: bytes) -> int:
    return int.from_bytes(b, "little", signed=False)

def parse_f32le(b: bytes) -> float:
    import struct
    return struct.unpack("<f", b)[0]

def parse_ld6001_frame(frame: bytes) -> dict:
    if len(frame) < 33:
        raise ValueError("frame too short")

    if frame[:8] != HEADER:
        raise ValueError("bad header")

    total_length = parse_u32le(frame[8:12])
    if total_length != len(frame):
        raise ValueError("length mismatch")

    frame_no = parse_u32le(frame[12:16])
    tlv1 = parse_u32le(frame[16:20])
    point_length = parse_u32le(frame[20:24])
    tlv2 = parse_u32le(frame[24:28])
    track_length = parse_u32le(frame[28:32])

    if tlv1 != 1:
        raise ValueError("unexpected TLV1")
    if tlv2 != 2:
        raise ValueError("unexpected TLV2")
    if point_length != 0:
        raise ValueError("unexpected point payload")
    if track_length % 32 != 0:
        raise ValueError("invalid track length")
    if total_length != 33 + track_length:
        raise ValueError("inconsistent frame sizing")

    track_data = frame[32:32 + track_length]
    checksum = frame[32 + track_length]

    calc = xor_bytes(frame[12:16] + track_data)
    if calc != checksum:
        raise ValueError("checksum mismatch")

    people = []
    for i in range(track_length // 32):
        base = i * 32
        rec = track_data[base:base + 32]
        person = {
            "reserved": parse_u32le(rec[0:4]),
            "id": parse_u32le(rec[4:8]),
            "x": parse_f32le(rec[8:12]),
            "y": parse_f32le(rec[12:16]),
            "z": parse_f32le(rec[16:20]),
            "vx": parse_f32le(rec[20:24]),
            "vy": parse_f32le(rec[24:28]),
            "vz": parse_f32le(rec[28:32]),
        }
        people.append(person)

    return {
        "frame_number": frame_no,
        "people": people,
    }
```

### 17.2 Stream parser pseudocode

```python
HEADER = bytes([1, 2, 3, 4, 5, 6, 7, 8])

buffer = bytearray()

def feed(data: bytes):
    buffer.extend(data)

    while True:
        idx = buffer.find(HEADER)
        if idx < 0:
            if len(buffer) > 7:
                del buffer[:-7]
            return

        if idx > 0:
            del buffer[:idx]

        if len(buffer) < 12:
            return

        total_length = int.from_bytes(buffer[8:12], "little")
        if total_length < 33:
            del buffer[0]
            continue

        if len(buffer) < total_length:
            return

        frame = bytes(buffer[:total_length])

        try:
            decoded = parse_ld6001_frame(frame)
            emit(decoded)
            del buffer[:total_length]
        except ValueError:
            del buffer[0]
```

---

## 18. Semantics of reported target data

Each detailed-mode frame is a **snapshot of the current tracked scene**.

For every tracked person, the module outputs:
- an integer **ID**,
- current position (`x`, `y`, `z`),
- current velocity (`vx`, `vy`, `vz`).

### Interpreting IDs

The manual calls this “personnel identification number” but does not define lifecycle guarantees. The natural operational assumption is:
- IDs are stable while the tracker maintains the target,
- IDs may be reused later after tracks disappear.

Host software should therefore treat IDs as **track-local identities**, not globally persistent identities across long sessions.

### Interpreting velocities

Velocity fields represent the instantaneous estimated motion components in the same coordinate axes as position.

### Interpreting Z

Because the unit is ceiling-mounted and looking downward, `z` represents vertical position or effective target height in the module’s model. Its absolute meaning may vary somewhat with installation height and calibration.

---

## 19. Host-computer mode `AT+DEBUG=2`

The manual shows a vendor PC application in this mode.

The screenshot and description indicate:
- select the serial port,
- use baud `115200` in that example,
- click “Open serial port”,
- then click “Start”.

The vendor tool display includes:
- a 2D XY view,
- target positions,
- angle/height-related controls or displays.

### Important limitation

The manual does not document the machine-readable data format for `DEBUG=2`. Therefore this mode should be treated as **vendor-tool mode**, not as a stable documented integration protocol.

For programmatic integrations, prefer **`AT+DEBUG=3`**.

---

## 20. Hardware/tools mentioned by the vendor

The manual lists the following environment components:

| Item | Description |
|---|---|
| Radar module | HLK-LD6001A-60G |
| USB-to-TTL module | For serial configuration, calibration, and related functions |
| USB extension cable | Connects PC to USB-to-TTL module |
| ST-LINK downloader | Used for firmware upgrade and development/debugging |

### Practical note

Only the UART interface is necessary for ordinary integration. ST-LINK is relevant for firmware-level work, not routine use.

---

## 21. Implementation recommendations

### 21.1 Strong recommendations

- Use a **stable 3.3 V / 1 A** power supply.
- Use **`AT+DEBUG=3`** for all parser-based applications.
- Implement **stream resynchronization**.
- Validate:
  - header,
  - frame length,
  - track length,
  - checksum.
- Keep command/response handling separate from binary frame parsing.
- Support configurable baud rate and command retry.

### 21.2 Do not assume

- that UART reads align with frame boundaries,
- that vendor-tool baud equals your module baud in all circumstances,
- that IDs are globally unique forever,
- that a missing person means “no movement”; disappearance timers may delay removal.

### 21.3 Useful derived host-side model

A practical host-side object model is:

```text
RadarFrame
  frame_number: uint32
  people: list[PersonTrack]

PersonTrack
  id: uint32
  x, y, z: float32
  vx, vy, vz: float32
  reserved: uint32
```

---

## 22. Known ambiguities in the vendor documentation

The original manual leaves several things implicit or slightly inconsistent. For correctness, these should be handled deliberately.

### 22.1 Baud-rate ambiguity

- command table: default baud is `921600`
- host-tool example: `115200`

Best interpretation: the documented default command/serial setting is `921600`, while the vendor tool example may reflect a different configuration or a tool-specific setup.

### 22.2 Terminology inconsistency

The manual alternates among:
- protocol mode,
- demo mode,
- debug mode.

The command table is the most authoritative mapping. For implementation:
- `DEBUG=0` = simple protocol
- `DEBUG=3` = detailed tracking protocol

### 22.3 Unit ambiguity in frame payload

The manual explicitly labels configuration commands in **centimeters** but does not label payload coordinates in the binary protocol. The numeric example strongly suggests **meters** and **meters/second**.

### 22.4 Point-cloud placeholder

The detailed protocol includes a point-cloud TLV but documents it as always zero-length. Treat this as a reserved section currently unused by documented firmware.

---

## 23. Quick-reference tables

### 23.1 Most important commands

| Purpose | Command |
|---|---|
| Start | `AT+START\n` |
| Stop | `AT+STOP\n` |
| Reset | `AT+RESET\n` |
| Read current parameters | `AT+READ\n` |
| Restore defaults | `AT+RESTORE\n` |
| Select detailed protocol | `AT+DEBUG=3\n` |
| Set baud | `AT+BAUD=...\n` |
| Set heartbeat interval | `AT+HEATIME=...\n` |
| Set installation height | `AT+HEIGHTD=...\n` |
| Set radial range | `AT+RANGE=...\n` |

### 23.2 Most important frame facts

| Item | Value |
|---|---|
| Detailed-mode header | `01 02 03 04 05 06 07 08` |
| Simple-mode header | `55 AA` |
| Integer endianness | little-endian |
| Float encoding | IEEE-754 little-endian `float32` |
| Per-target record size | `32` bytes |
| Target count derivation | `track_length / 32` |
| Detailed checksum scope | `frame_number + track_data` |
| Minimum detailed frame size | `33` bytes |

---

## 24. Minimal integration checklist

1. Wire `3V3`, `GND`, `TX`, `RX`.
2. Ensure a supply that can handle startup/RF peaks.
3. Open UART, usually beginning with `921600`.
4. Send `AT+DEBUG=3\n`.
5. Configure installation geometry if needed.
6. Send `AT+START\n`.
7. Read binary stream.
8. Search for header `01 02 03 04 05 06 07 08`.
9. Read `length`.
10. Validate `track_length`, frame size, and checksum.
11. Decode each 32-byte target record.
12. Publish tracks to the application.

---

## 25. Reference test vector

Use this exact frame as a parser test vector:

```text
01 02 03 04 05 06 07 08 40 00 00 00 A3 01 00 00 01 00 00 00 00 00 00 00 02 00 00 00 20 00 00 00 00 00 00 00 00 00 00 00 21 28 96 BF CB 85 20 40 9A AB A3 3E 8A BD C1 3D 50 98 99 BD 40 52 C3 3A CC
```

Expected decode:

```text
frame_number = 419
num_people   = 1

person[0].reserved = 0
person[0].id       = 0
person[0].x        ≈ -1.1731
person[0].y        ≈  2.5082
person[0].z        ≈  0.3197
person[0].vx       ≈  0.0941
person[0].vy       ≈ -0.0750
person[0].vz       ≈  0.0015

checksum = 0xCC
```

---

## 26. Final implementation model

The HLK-LD6001A should be thought of as a **stateful tracking sensor** that continuously emits scene snapshots over UART. In detailed mode, every frame contains the current set of tracked persons, each encoded as:
- a track ID,
- 3D position,
- 3D velocity.

For reliable integration, the essential requirements are:
- correct power design,
- correct mode selection (`DEBUG=3`),
- correct little-endian decoding,
- correct checksum scope,
- correct stream resynchronization.
