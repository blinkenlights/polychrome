# HLK-LD6001-60G Smart Air-Conditioning Radar — Developer Documentation

Version basis:
- HLK-LD6001-60G User Manual **V1.1** (vendor revision marked `2024-8 A/0`).

> **Important — different product than HLK-LD6001A-60G.**
> This document covers the **HLK-LD6001-60G** ("LD6001"), a wall-mounted 4T3R 60 GHz radar marketed by Hi-Link as a "smart air-conditioning radar". It is a **different product** from the **HLK-LD6001A-60G** ("LD6001A"), which is a ceiling-mounted human-trajectory tracker covered in [`hlk_ld6001a_reference.md`](./hlk_ld6001a_reference.md). Despite the closely related names, the two modules differ in:
> - antenna configuration (4T3R vs. the LD6001A internal layout),
> - operating voltage (**5 V** vs. 3.3 V on the LD6001A),
> - serial-port voltage level (**5 V TTL** vs. 3.3 V TTL on the LD6001A),
> - default baud rate (**9600** vs. 115200 on LD6001A V1.2),
> - intended installation (vertical wall at 2.2 m vs. ceiling at 2.5–3.0 m),
> - host interaction model (**host-driven query/response** vs. continuous push-streaming on the LD6001A),
> - documented protocol (referenced in a separate document not included in this repo; see §3.2).
>
> Do not assume any LD6001A integration code, command set, baud rate, or wiring will work with the LD6001.

---

## 1. Purpose and scope

This document is a developer-oriented rewrite of the vendor V1.1 manual for the HLK-LD6001-60G radar module. It is intended as a practical reference for:
- firmware and embedded developers integrating the module,
- AI coding agents generating integrations,
- engineers configuring or validating deployments.

The two areas the V1.1 manual itself emphasises — and that this document treats with priority — are:
- the **initialization sequence**,
- the **available configuration options** exposed through the vendor host-computer tool.

The V1.1 manual is comparatively terse and notably defers the actual wire protocol to a separate document (see §3.2). Where V1.1 is silent or ambiguous, this document calls it out explicitly rather than guessing.

---

## 2. Device overview

The LD6001 is a **4T3R fully integrated 60 GHz mmWave radar module** (four transmit channels, three receive channels). It is positioned for indoor occupancy and presence applications — vendor copy specifically uses smart air-conditioning as the application archetype.

### Documented capabilities

- detect the **regional location** of human bodies,
- **count people** (vendor specifies "within 8 people"),
- estimate **walking trajectory**.

### Front/back orientation

- The **front** of the module has the antenna and is the side that **faces upward** during installation (the module is wall-mounted with the antenna tilted toward the ceiling — see §5).
- The **back** carries the connector socket and burning port.

> **Iteration note.** V1.1 explicitly warns that physical PCB layout may change in later silicon iterations and that the included photographs are reference only.

---

## 3. Key specifications

### 3.1 Module parameter table (V1.1 §2)

| Parameter | Value | Unit |
|---|---|---|
| Operating frequency | 60 | GHz |
| Transmit power | 12 | dBm |
| Modulation | FMCW (FM continuous wave) | — |
| Sweep bandwidth | 4 | GHz |
| Antenna beam width (horizontal) | ±60 | ° |
| Antenna beam elevation width | ±30 | ° |
| Maximum detection distance | 8 | m |
| Operating voltage | **5** | V |
| Average power consumption | 1.1 | W |
| Operating temperature | -15 to +70 | °C |
| Module size | 60 × 30 | mm |
| Startup time | 3 | s |

### 3.2 Protocol document — not included

V1.1 §3.4 ends with:

> *"For specific protocol, please refer to the document 'Intelligent Air Conditioning Radar LD6001 Protocol Description Document V1.1.pdf'."*

That protocol-specification document is **not part of this repository**. Without it:
- the on-wire command and response framing is not documented here,
- the byte-level structure of "read target" responses is not documented here,
- the specific command opcodes for "query", "read target", "set sensitivity", and "set interval" are not documented here.

Anyone implementing a parser must either obtain that companion document from Hi-Link or capture the protocol empirically from the vendor host-computer tool (see §7 and §10).

This document therefore stops at the **interaction model and configuration semantics** that V1.1 explicitly describes, and does not invent protocol details.

---

## 4. Mechanical and PCB notes (V1.1 §3.1)

### 4.1 PCB tolerances

| PCB feature size | Tolerance |
|---|---|
| 0–10 mm | ±0.10 mm |
| 10–150 mm | ±0.20 mm |

### 4.2 Connectors on the module

| Connector | Specification |
|---|---|
| Surface socket (communication interface) | Horizontal, 4 pins, **2.0 mm pin spacing**, green |
| Burning / programming port | 2.54 mm pin spacing, 0.9 mm aperture; pin function defined by physical silkscreen marking |

The communication-interface socket is the one exposed to the host (host UART). The burning port is for firmware programming/debugging only and is not required for normal integration.

---

## 5. Installation

V1.1 §3.2 specifies the intended installation as:

- **mounted on a vertical wall**,
- at a height of **2.2 m**,
- with the front of the module (antenna side) **tilted upward by 10°**.

The vendor states this is the recommended geometry "for the best effect", but allows that the user may install slightly higher or adjust the tilt angle "as needed", with actual results being subject to empirical test.

### 5.1 Radiation pattern (V1.1 §3.3)

| Axis | Coverage |
|---|---|
| Horizontal | ±60° |
| Elevation | ±30° |

Note the elevation coverage is **narrower** than the horizontal coverage. This is consistent with the wall-mounted, slightly-tilted-up installation: the module is intended to surveil a horizontal corridor of the room rather than a hemispherical dome.

### 5.2 Practical implications

- a single LD6001 covers a horizontal arc out to roughly 8 m at ±60°,
- the elevation envelope (±30°) means the module is **not** appropriate for ceiling-mount full-room coverage; that case is what the LD6001A is designed for,
- any obstruction within the elevation cone (low furniture, wall fixtures) will degrade detection.

---

## 6. Electrical interface

### 6.1 Pinout

V1.1 documents the communication-interface socket as a 4-pin surface socket. The wiring order is given **from bottom to top** as:

| Pin (bottom → top) | Name | Function |
|---|---|---|
| 1 | `VCC` | Power supply input, **DC 5 V** |
| 2 | `RX` | Serial-port receive (into module), **TTL 5 V level** |
| 3 | `TX` | Serial-port transmit (from module), **TTL 5 V level** |
| 4 | `GND` | Ground |

> **Voltage warning.** The LD6001 expects **5 V** for both supply and UART signal levels. Driving its `RX` pin from a 3.3 V host UART may fail to register a high. Driving a 3.3 V host's `RX` from the LD6001's 5 V `TX` may damage the host. Use a level shifter between the LD6001 and any 3.3 V microcontroller.

### 6.2 Electrical figures of merit

V1.1 does not provide a detailed absolute-maximum / typical-operating table the way the LD6001A V1.2 manual does. The available figures are:

- Operating voltage: **5 V**
- Average power consumption: **1.1 W** → average current ≈ **220 mA at 5 V**
- Startup time: **3 s** (allow this much time after power-on before issuing the first command)

V1.1 does not document peak/transient current; size the supply with margin. Peak current during RF operation will be substantially higher than the average; a supply rated for **at least 1 A at 5 V** is a safe starting point for hardware design.

---

## 7. Host communication model

The LD6001 is controlled and read over its **TTL UART** by a host (PC or microcontroller). V1.1 §3.4 describes the interaction model from the perspective of the vendor host-computer tool:

1. open the serial port at the module's baud rate,
2. issue a **query** to obtain software/hardware version and confirm device state,
3. confirm `device working status = initialized` and `radar module = on`,
4. **actively poll** for target data at a chosen interval.

### 7.1 Documented baud rate

The vendor host-computer tool uses **9600 baud** by default. V1.1 does not document any other baud rate, nor a command for changing it. Treat **9600** as the operative default.

### 7.2 Polling, not push-streaming

V1.1 §3.4 explicitly states that target coordinate data is obtained through **active query** by the host:

> *"The target coordinate data is obtained through active query, so the interval time is to set how often to query the target status."*

This is fundamentally different from the LD6001A, which continuously pushes detailed binary frames at the radar's processing cadence. The LD6001's host must drive the conversation: it issues a "read target" request and the module replies.

### 7.3 What V1.1 does not document about the protocol

The V1.1 manual does **not** specify:
- the byte-level command framing,
- the response framing,
- whether commands are ASCII (`AT+...`) or binary,
- checksum or framing rules,
- the data layout of the "read target" response (coordinates, count, IDs, units),
- whether sensitivity and interval are persisted on the module or only kept by the host tool.

All of those are described as being in the separate "Intelligent Air Conditioning Radar LD6001 Protocol Description Document V1.1.pdf" (see §3.2) which is not present in this repository.

For an integration, the practical options are:
- obtain the vendor protocol document from Hi-Link, or
- capture the protocol empirically: connect the vendor host-computer tool to the module via a serial sniffer (or a software port-monitor), exercise each button on the tool (query, set sensitivity, set interval, read target), and record both directions of the UART traffic.

---

## 8. Initialization sequence

This is the runtime startup sequence implied by V1.1 §3.4. Use it as the canonical bring-up flow.

### 8.1 Hardware bring-up

1. Wire the module:
   - `VCC` → stable 5 V supply (sized for at least the average 220 mA, with peak headroom; ≥ 1 A recommended),
   - `GND` → host ground,
   - module `TX` → host UART `RX` (5 V level — level shifter required for 3.3 V hosts),
   - module `RX` → host UART `TX` (5 V level — level shifter required for 3.3 V hosts).
2. Apply 5 V power.
3. Wait **at least 3 s** (the documented startup time) before issuing any command.

### 8.2 Serial bring-up

4. Open the host UART at **9600 baud**, 8 data bits, no parity, 1 stop bit (8N1 is the conventional default; V1.1 does not state otherwise).

### 8.3 Module-state probe (the "query" step)

5. Issue the **query** command (vendor name; opcode and framing live in the separate protocol document).

   The expected response, per V1.1, contains:
   - software version,
   - hardware version,
   - **device working status** — must read `initialized`,
   - **radar module state** — must read `on`.

6. Verify both state fields:
   - if `device working status` is **not** `initialized`, the module is not yet ready; wait and re-query or treat as a fault,
   - if `radar module` is **not** `on`, the module is not actively scanning; the vendor host-computer tool implies there is a way to bring it on (the tool exposes this), but V1.1 does not document the on/off command in the manual itself.

### 8.4 Begin polling

7. Once the module reports `initialized` and `on`, begin issuing the **read target** command at the chosen polling interval (default 200 ms — see §9).
8. Each `read target` response yields the current set of detected targets (positions, trajectories, counts; the exact byte format is in the separate protocol document).

### 8.5 Initialization sequence (compact form)

```text
power on (5 V)
wait ≥ 3 s
open UART @ 9600 8N1
query                      # expect: SW/HW version, status=initialized, radar=on
verify status & radar state
loop every <interval ms>:  # default 200 ms; configurable per §9.1
    read target
    decode response
```

### 8.6 What this initialization does not require

V1.1 does **not** document any required configuration writes before polling can begin. With the factory defaults — 9600 baud, 200 ms interval, and (presumably) "Normal" sensitivity — a host can go directly from query → read target without any setter command. Configuration writes (§9) are optional tuning steps.

### 8.7 Practical timing recommendation

The radar's natural sampling cadence is not stated. The vendor's default 200 ms polling interval (5 Hz) is therefore the supported rate; the manual gives no guidance for polling faster than that. Implementations should treat 200 ms as the floor unless empirical evidence supports otherwise.

---

## 9. Configuration options

V1.1 documents exactly **two user-facing configuration parameters**, plus the implicit baud rate. None of the V1.1 text specifies the wire format for setting them; that lives in the separate protocol document (see §3.2). The semantic descriptions below are the authoritative part of V1.1.

### 9.1 Polling interval ("Interval time")

| Property | Value |
|---|---|
| Meaning | How often the host issues a "read target" query, expressed as the inter-query period |
| Default | **200 ms** (5 Hz) |
| Effect on host | Sets host polling cadence |
| Effect on module | Module replies on demand to each query; lowering the interval increases UART load and host CPU load but does not change radar physics |
| Persistence | V1.1 does not state whether the value is stored on the module or only in the host-computer tool — most likely the latter, since polling is host-driven |

#### Implementation guidance

- Treat "interval time" as a **host-side** parameter unless empirical capture proves the module also persists it.
- Validate that responses arrive between consecutive queries; if responses lag the query rate, increase the interval.
- Do not assume reducing the interval below 200 ms produces correspondingly fresher data; the underlying radar frame rate is unspecified.

### 9.2 Sensitivity mode

V1.1 §3.4 documents two named sensitivity modes:

| Mode | Behaviour (verbatim semantics from V1.1) |
|---|---|
| **Normal mode** | After a target enters the detection area, tracking time is **longer** but accuracy is **higher** |
| **High sensitivity mode** | Targets entering the detection area are **quickly triggered and displayed**, but the probability of false detections in the initial state is **higher** and accuracy is **slightly affected** |

#### Choosing a mode

- **Normal**: prefer when stable, accurate occupancy or trajectory information matters more than fast appearance reaction. Appropriate for HVAC scheduling, occupancy-driven climate control, and analytics.
- **High sensitivity**: prefer when fast wake-up reaction matters more than steady-state accuracy. Appropriate for "presence detected" toggles, motion-triggered awakening of downstream systems, and low-latency trip events that can absorb spurious detections.

V1.1 does **not** document:
- additional sensitivity levels beyond these two,
- per-axis or per-region sensitivity,
- ramp/hysteresis behaviour between the two modes,
- how (or whether) the chosen mode is persisted across power cycles.

### 9.3 Baud rate

V1.1 only mentions baud rate once, in the host-tool description: *"the baud rate defaults to 9600"*. There is no documented command for changing it. For all practical purposes:

- treat **9600 baud** as the operative speed,
- if a unit responds at a different baud rate, it is operating outside V1.1's documented behaviour.

### 9.4 Configuration scope summary

| Parameter | Where set | Default | Persisted on module? |
|---|---|---|---|
| Polling interval | Host (host loop or vendor tool) | 200 ms | No (host-driven) |
| Sensitivity | Sent over UART | "Normal" (implied) | Not documented in V1.1 |
| Baud rate | UART configuration on both sides | 9600 | Not documented in V1.1 |

---

## 10. Vendor host-computer tool (V1.1 §3.4)

V1.1's "host computer test instructions" describe a Windows-side application supplied by the vendor. Its operational flow is:

1. Connect the module to the PC via the serial port.
2. Open the host-computer tool.
3. Select the matching COM port; the tool defaults to **9600 baud**.
4. Click **query** to obtain SW/HW version and to confirm `device working status = initialized` and `radar module = on`.
5. Click **read target** to begin showing position and trajectory of people in range.

Configuration in the tool exposes:
- **Interval time** (§9.1),
- **Sensitivity** (§9.2: Normal / High).

### 10.1 Practical notes

- The host-computer tool is a **reference UI**, not a documented integration API. It is the simplest way to confirm that a given module is alive, that its current baud rate is 9600, and that "query" / "read target" return plausible data.
- For programmatic integration, use the vendor host-computer tool only as a known-good behavioural reference. Any bytes you observe between the tool and the module map directly onto what your own integration must transmit and decode.
- If the protocol document (§3.2) is unavailable, the tool plus a serial sniffer is the most pragmatic way to recover the framing.

---

## 11. Differences from HLK-LD6001A-60G

The two modules share branding and a 60 GHz front-end family but are otherwise distinct. The differences below are summarised for engineers cross-shopping or moving an integration from one to the other.

| Aspect | HLK-LD6001-60G (this doc) | HLK-LD6001A-60G (separate doc) |
|---|---|---|
| Documented role | Smart air-conditioning radar (presence/count/trajectory) | Human-trajectory radar |
| Antenna config | 4T3R | Internal, ceiling-pattern |
| Installation | Wall, 2.2 m, antenna tilted up 10° | Ceiling, 2.5–3.0 m, antenna down |
| Coverage | ±60° azimuth, ±30° elevation | ±60° azimuth and elevation |
| Detection range | up to 8 m | 0.5 m to 8 m |
| Supply voltage | **5 V** | 3.3 V |
| UART signal level | **5 V TTL** | 3.3 V TTL |
| Default baud | **9600** | 115200 (V1.2) |
| Communication model | **Host-driven query/response** | Continuous push-streaming (binary frames) |
| Per-target IDs/positions/velocities | Not documented in V1.1 | Documented in V1.2 (`float32` X/Y/Z/Vx/Vy/Vz) |
| Average power | 1.1 W | 0.3 W |
| Module size | 60 × 30 mm | 29.36 × 28 mm |
| Startup time | 3 s | Not documented |
| Protocol description | **In a separate document, not in this repo** | Inline in V1.2 (detailed protocol over `AT+DEBUG=3`) |

> Treat the LD6001 and LD6001A as **separate products** for all integration purposes. Code, wiring, baud, AT commands, and frame layouts from the LD6001A integration are **not** transferable.

---

## 12. Open questions / what V1.1 does not specify

For honesty and to guide further investigation, the following are *not* documented in V1.1:

1. **Wire-level command and response framing** — referenced separately (§3.2).
2. **Coordinate frame and units** — the manual only says "position" and "trajectory", with no statement of units, axes, or origin.
3. **Maximum number of simultaneously reported targets** beyond the "within 8 people" capacity statement.
4. **Whether "query" and "read target" are command opcodes or compound interactions.**
5. **Whether sensitivity and interval persist across power cycles.**
6. **Any explicit on/off control of the radar module** — V1.1 implies the host-computer tool can put the module into the `on` state, but no command is documented in the V1.1 manual itself.
7. **Whether changing the baud rate is supported at all.**
8. **Behaviour at radar module state transitions** (cold start → initialized → on; possible idle/sleep modes).
9. **Error codes or fault reporting in responses.**
10. **Per-target IDs or track persistence semantics.**

When V1.1 disagrees with a separately-obtained protocol document or with empirical capture, prefer the empirical evidence and call out the discrepancy, the same way the LD6001A reference does.

---

## 13. Implementation recommendations

### 13.1 Hardware

- Use a stable **5 V supply with ≥ 1 A capability** (to absorb RF transients beyond the 220 mA average).
- Place a **5 V↔3.3 V level shifter** between the module and any 3.3 V host UART.
- Allow **≥ 3 s** between power-on and the first UART command.

### 13.2 Serial

- Open at **9600 8N1**.
- Treat the link as **half-duplex from the protocol's standpoint**: the host issues commands, the module replies. There is no documented unsolicited push.
- Implement timeouts: if a command does not produce a response within a sensible bound (a few hundred ms for "read target"), treat it as a missed reply rather than a stream desync.

### 13.3 Polling loop

- Default to a **200 ms** interval.
- Make the interval configurable.
- Drop targets locally if no response arrives for several poll cycles, rather than assuming a missing response means "no targets".

### 13.4 Sensitivity selection

- Make sensitivity a deployment-time choice, not a runtime auto-tuned parameter.
- Default to **Normal** unless the application is specifically a fast-trigger ("did anyone walk in?") use case.

### 13.5 Initialization robustness

- Always issue a **query** first and verify both `device working status = initialized` and `radar module = on` before starting the polling loop.
- Re-issue the query if either field is wrong, with a sensible backoff.

### 13.6 Protocol implementation

- Do not invent the wire format. Either:
  - obtain the "Intelligent Air Conditioning Radar LD6001 Protocol Description Document V1.1.pdf" from the vendor, or
  - capture the format from the vendor host-computer tool with a serial sniffer.
- Document the captured byte layout in this file (or a sibling) once it is confirmed empirically.

---

## 14. Quick reference

### 14.1 Power and serial

| Item | Value |
|---|---|
| Supply voltage | 5 V |
| Recommended supply current | ≥ 1 A |
| UART signal level | 5 V TTL |
| UART baud rate | 9600 (8N1) |
| Startup time | ≥ 3 s before first command |

### 14.2 Initialization

| Step | Action |
|---|---|
| 1 | Power on (5 V) and wait ≥ 3 s |
| 2 | Open UART @ 9600 8N1 |
| 3 | Issue **query** |
| 4 | Verify `device working status = initialized` and `radar module = on` |
| 5 | Start the polling loop with **read target** at the configured interval |

### 14.3 Configuration knobs (per V1.1)

| Knob | Default | Notes |
|---|---|---|
| Polling interval | 200 ms | Host-driven cadence |
| Sensitivity | Normal | Alternative: High (fast trigger, lower accuracy) |
| Baud rate | 9600 | No documented mechanism to change |

### 14.4 Don't assume

- That the LD6001 behaves like the LD6001A. **It does not.** See §11.
- That a 3.3 V microcontroller can speak to it directly. **It cannot.** See §6.1.
- That the module pushes data continuously. **It does not.** See §7.2.
- That the protocol is documented in V1.1. **It is not.** See §3.2.
