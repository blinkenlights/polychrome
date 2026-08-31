# Recording Subsystem — Design & Architecture

This document describes the recording subsystem: what it does, why it is built
the way it is, and the important details for anyone extending or debugging it.

For day-to-day usage see [`recording.md`](./recording.md).

---

## Goals & constraints

The installation produces pixel animations that are sent to LED panels over
UDP/protobuf, and radar sensors track motion that influences those animations.
We want to **record the animations sent to the panels** and **record the radar
data**, both for later **visualization** (playable video), not for
packet/firmware debugging.

Hard requirements that shaped every decision:

1. **Never crash or influence the running application.** Recording is
   observational. A recording failure must degrade the recording only — never
   the mixer, the broadcaster, the apps, or the sensors.
2. **Visualization, not forensics.** We capture the logical, displayable frame
   (not the hardware wire format), and we don't record audio.
3. **A movie at the end.** Recordings must convert to standard video. Panels →
   one video per panel plus a mixed video; radar → a top-down scope video.
4. **Append-only files, no database.** Simple, cheap to write, easy to convert.
5. **Also streamable to a remote server**, not only to a local file.
6. **The number of input devices is not fixed** — panel count is read from the
   installation at record time and stored in the recording.

---

## Data flow & tap points

### Panels (animations → LEDs)

```
Apps ──► Mixer ──► (compose / transition / mask) ──► RGBFrame / WFrame
                     │
                     ├─ PubSub topic "mixer": {:mixer, {:frame, frame}}   ◄── PanelRecorder taps here
                     │
                     └─ Untangle (hardware wire order) ─► Protobuf.split_and_encode ─► Broadcaster ─► UDP ─► panels
```

The recorder subscribes to the mixer's `"mixer"` PubSub topic and records the
`{:mixer, {:frame, frame}}` messages. This is deliberately **upstream of
`Untangle` and `split_and_encode`**, so the recorded frame is:

- the **logical** frame (not the hardware-scrambled pixel order), and
- **full resolution and un-split** (not the two UDP packets).

This is the same feed the simulators consume, so it is a proven, side-effect-free
tap. The pixel byte layout the mixer produces (see `Octopus.Mixer.canvas_to_frame/4`)
is **panel-major, then row-major within each panel**:

```
for panel <- 0..num_panels-1, y <- 0..panel_height-1, x <- 0..panel_width-1 -> {r,g,b}
```

which is exactly why splitting into per-panel videos is a trivial fixed-stride
slice.

Two quirks handled by the recorder:

- The `{:mixer, {:frame, ...}}` message fires **once per UDP split part**, so
  each frame arrives twice back-to-back. The recorder de-duplicates
  byte-identical frames that arrive within 5 ms of each other.
- Frames are **event-timed** (emitted when the mixer renders, plus a ~1 s idle
  frame), not at a fixed rate. Timing is preserved as per-frame timestamps and
  resampled to a constant rate at encode time.

### Radar (sensors → animations)

```
Radar sensors ──► Octopus.Radar.Sensor ──► Transform (local → global frame)
                     │
                     └─ PubSub topic "radar:hlk6001": {:radar_frame, device_id, %Frame{}}  ◄── RadarRecorder taps here
```

Track positions are already mapped into the **installation global frame**
(meters, origin at the installation center) by `Octopus.Radar.Transform` before
publishing, so all sensors share one coordinate system and merge naturally into
a single scope.

> The firmware proximity sensors (`ProximityEvent` via the broadcaster) are
> intentionally **not** recorded — only the radar layer is relevant.

---

## Safety design (how "never influence the app" is guaranteed)

- **Passive subscriber.** Recorders only ever *receive* PubSub broadcasts.
  `Phoenix.PubSub.broadcast` does not link and does not wait for subscribers, so
  the mixer/sensors never block on, or fail because of, a recorder.
- **Subscribe only while active.** When not recording, nothing is subscribed —
  zero message traffic, zero overhead. Disabled = truly off.
- **No calls into the recorder from the hot path.** The producers never call the
  recorder; communication is one-way via PubSub.
- **Bounded mailbox with drop-on-overload.** The only risk a passive subscriber
  poses is an unbounded mailbox if it can't keep up. Each recorder checks its own
  `message_queue_len` and drops frames once it exceeds `max_queue`, so memory
  can't balloon. Dropped frames only shorten the recording.
- **Crash isolation.** Every incoming frame is processed inside
  `try/rescue/catch`; a bad frame or sink error degrades to a dropped frame (or a
  clean stop on sink error), never a crash. The whole subsystem lives under
  `Octopus.Recording.Supervisor` (`:one_for_one`), so even an unexpected crash
  restarts only the recorder.
- **Bounded network I/O.** The remote sink uses a connect timeout (unreachable
  server fails the *start*, doesn't hang) and a per-write send timeout with
  `send_timeout_close`, so a stalled server produces a bounded error rather than
  an indefinite block. Combined with drop-on-overload, a slow network only
  degrades the recording.
- **Additive-only touch to the app.** The single change to existing runtime code
  is a new `Octopus.Mixer.unsubscribe/0` (mirrors `subscribe/0`) — no behavioral
  change — plus adding `Octopus.Recording.Supervisor` to the supervision tree.

---

## Shared timeline & alignment

Both recorders stamp each frame with `offset_ms`, measured from a **monotonic**
origin captured at session start (`System.monotonic_time(:millisecond)`), and
store the wall-clock start (`System.system_time(:millisecond)`) in their header.
Monotonic time is used so frame timing is stable and immune to NTP jumps.

`Octopus.Recording.Session` starts the panel and radar recorders with the **same
`start_mono_ms` and `started_at_ms`**, so their offsets share one zero. That's
what lets the encoders (which resample to the same fps) emit `mixed.mp4` and
`radar.mp4` with matching frame counts and durations, aligned frame-for-frame.

The radar recorder uses `Frame.received_at` (already monotonic ms) for its
timestamps, so the recorded time reflects when the frame actually arrived, not
when the recorder happened to process it.

---

## File formats

### `.octorec` (panels) — `Octopus.Recording.Format`

Append-only binary. All integers big-endian. Grayscale (`WFrame`) frames are
normalized to RGB (`r = g = b = w`) on write so the stream is uniform and the
encoder never branches on frame type.

Header (26 bytes, once):

| Field | Type | Notes |
|-------|------|-------|
| magic | 8 bytes | `"OCTOREC1"` |
| version | u8 | format version (1) |
| kind | u8 | `0` = rgb (only value emitted) |
| num_panels | u16 | from the installation at record time |
| panel_width | u16 | |
| panel_height | u16 | |
| reserved | u16 | `0` |
| started_at_ms | u64 | wall-clock ms at start |

Record (`4 + frame_bytes` bytes, repeated):

| Field | Type | Notes |
|-------|------|-------|
| offset_ms | u32 | monotonic ms since start |
| pixels | `frame_bytes` | RGB, panel-major / row-major |

where `frame_bytes = num_panels * panel_width * panel_height * 3`. Panel `n`
occupies the slice `[n * panel_bytes, (n+1) * panel_bytes)` with
`panel_bytes = panel_width * panel_height * 3`, and each slice is already a
ready-to-use RGB image.

**Why binary + fixed size:** at up to 60 fps this is the cheapest possible write
(append raw bytes, no per-frame parsing), and fixed geometry means the encoder
can slice panels with pure offset math. A database row per frame would be far too
much overhead; the file is the natural container.

### `radar.jsonl` (radar) — `Octopus.Recording.RadarFormat`

Line-delimited JSON. Radar is low-volume and variable-length (a frame has a
variable number of tracks), so a text format is the pragmatic choice: easy to
inspect, append, and parse.

Metadata line (first line):

```json
{"v": 1, "started_at_ms": 1700000000000, "world_radius_m": 8.0}
```

Frame line (one per radar frame):

```json
{"t": 123, "dev": 1, "n": 42,
 "tracks": [{"id": 7, "x": 1.2, "y": -0.5, "z": 2.0, "vx": 0.1, "vy": 0.0, "vz": 0.0}]}
```

`t` is `offset_ms` (shared timeline), `dev` the sensor device id, `n` the device
frame number, and track coordinates are in the global frame (meters, m/s).

---

## Module structure

```
Octopus.Recording                    facade: config + start/stop/status (session-level)
Octopus.Recording.Supervisor         isolated :one_for_one subtree
  ├─ Octopus.Recording.PanelRecorder GenServer: taps mixer, writes .octorec
  ├─ Octopus.Recording.RadarRecorder GenServer: taps radar, writes .jsonl
  └─ Octopus.Recording.Session       GenServer: shared clock + session dir; owns boot auto-start

Octopus.Recording.Format             .octorec encode/parse (pure)
Octopus.Recording.RadarFormat        radar JSONL encode/parse (pure)

Octopus.Recording.Sink               behaviour: open/1, write/2, close/1, describe/1
Octopus.Recording.Sink.File          local file (:raw + :delayed_write)
Octopus.Recording.Sink.Remote        TCP stream (bounded connect/send timeouts)

Octopus.Recording.Encoder            .octorec → per-panel + mixed video (ffmpeg)
Octopus.Recording.RadarEncoder       .jsonl → top-down scope video (ffmpeg)
Mix.Tasks.Octopus.Recording.Encode   offline CLI; accepts file or session dir
```

Supervisor child order matters: the recorders start before `Session` so the
session can drive (and auto-start) them once they're up.

### The `Sink` seam

Recorders write opaque `iodata` through a `Sink`. This is the extension point
that made remote streaming a small, self-contained addition: `Sink.File` and
`Sink.Remote` implement the same 4-callback behaviour, and the recorder is
agnostic to which is in use. New transports (e.g. an HTTP uploader) only need to
implement the behaviour.

---

## Encoding design

Both encoders are **offline** (a mix task), never part of the running app, so
`ffmpeg` and its CPU cost never touch the installation.

Shared approach:

1. **Resample** the event-timed records onto a constant fps using
   hold-last-frame semantics (step time in `1000/fps` ms increments; emit the
   most recent frame at or before each tick). This converts irregular timing into
   a standard constant-frame-rate movie.
2. Write raw `rgb24` frames to a temp file and hand them to `ffmpeg`
   (`-f rawvideo -pix_fmt rgb24 ...`), producing H.264 `yuv420p` MP4s. Temp files
   are always cleaned up.

**Panels** (`Encoder`):

- Per-panel video: slice panel `n`'s block each frame → native `pw x ph` image,
  upscaled by `--scale` with nearest-neighbour (crisp pixels).
- Mixed video: transpose the panel-major buffer into a row-major **strip**
  (`num_panels * panel_width` × `panel_height`) — the circular installation
  unrolled left-to-right in panel order.

**Radar** (`RadarEncoder`):

- At each tick, the scene is the **union of the most recent frame from each
  sensor** (grouped by `dev`), so all sensors appear together.
- Each track is drawn as a colour-coded dot (colour by track id) on a top-down
  view: origin centered, `+x` right, `+y` up, with a boundary ring and centre
  marker. World extent defaults to the recording's `world_radius_m`.

Pure helpers (`resample/2`, `panel_frame/3`, `strip_frame/2`, `scope_frames/2`,
`world_to_px/4`, `render/3`) are separated from the `ffmpeg` shell-out so they
can be unit-tested without `ffmpeg`.

---

## Configuration reference

```elixir
config :octopus, Octopus.Recording,
  enabled: false,            # Session auto-starts on boot when true
  output_dir: "recordings",  # base dir for sessions and standalone files
  max_queue: 600,            # per-recorder mailbox backlog → drop threshold
  sink: {:file, []}          # default sink for the low-level recorders
```

`sink` accepts `{:file, opts}` (opts may set `:dir` or a fixed `:path`) or
`{:remote, host:, port:, ...}`. Note the **Session always uses file sinks**
(both streams share a directory); the `sink` spec drives the low-level recorders
when started directly without an explicit `:sink_mod`.

---

## Testing

- Pure format/encoder logic is unit-tested (header round-trips, W→RGB
  normalization, resampling, panel slicing, strip transpose, radar scene merge,
  `world_to_px`).
- Recorders are tested end-to-end by broadcasting synthetic `{:mixer, {:frame,
  ...}}` / `{:radar_frame, ...}` messages and asserting the resulting files.
  Because a live mixer may emit blank idle frames onto the same topic, panel
  assertions filter to the test's own distinctive frames.
- The remote sink is tested against an in-test TCP listener (bytes arrive
  verbatim; unreachable server errors cleanly).
- `ffmpeg` end-to-end encode tests are tagged `:ffmpeg` and run with
  `mix test --include ffmpeg`; they no-op when `ffmpeg` is absent.

---

## Compression

Recordings can be gzip-compressed via a composable sink,
`Octopus.Recording.Sink.Gzip`, which wraps an inner sink (file or remote) and
compresses the stream with Erlang's built-in `:zlib`. This is deliberately
**dependency-free** so it runs on a Raspberry Pi without any native/cross-
compiled libraries (`zstd` was rejected for exactly this reason). Enable with
`compress: true` (config or per `start/1`); `gzip_level` (0..9) trades ratio for
CPU.

Design points:

- **Composability.** `Sink.Gzip.wrap/4` turns a resolved `{sink_mod, sink_opts}`
  into a gzip-wrapped one, adding a `.gz` suffix for file targets. It works
  identically over the file and remote sinks.
- **Crash safety.** A gzip stream is only fully valid once finalized on
  `close/1` (called on stop and on normal supervised shutdown). To bound loss
  from a hard VM crash, the stream is `:sync`-flushed every `flush_every` writes
  (default 200); a sync flush keeps the compression dictionary, so the ratio
  impact is negligible.
- **Transparent decode.** The encoders detect a `.gz` extension and
  `:zlib.gunzip` the file before parsing, so `mix octopus.recording.encode`
  needs no extra flags.

### Measured savings

Measured on 900-frame (~30 s) recordings for a 12x8x8 installation
(2,077,226 bytes raw), gzip level 6:

| Content | gzip savings | with temporal delta (XOR)+gzip |
|---------|--------------|--------------------------------|
| Busy full-colour animation | ~20–35% (1.3–1.5×) | ~59% (2.5×) |
| Text / sparse / mostly dark | 99%+ (100–800×) | 99.98% (6000×+) |
| Full-frame random noise | ~0% | ~0% |

The big lever is **temporal redundancy** (consecutive frames are nearly
identical). Generic gzip only partly exploits it because its 32 KB window spans
only ~14 frames; a temporal delta pre-pass (XOR each frame against the previous)
turns most bytes to zero and roughly doubles the ratio on busy content. A delta
pre-pass is a possible future addition to the format (it would need a format
flag and reversal in the encoder); it is **not** implemented today.

---

## Known limitations & gotchas

- **`ffmpeg` is required for encoding** (not for recording).
- **Compressed recordings are only finalized on a clean stop.** A hard VM crash
  can truncate the trailing gzip block; periodic sync-flushing bounds the loss
  but the very tail may be unreadable by one-shot `:zlib.gunzip`.
- **Radar recording requires the radar layer to be enabled**
  (`Octopus.Radar.enabled?()`); otherwise `radar.jsonl` contains only metadata.
- **Sessions are file-only.** Streaming both panels and radar to a remote server
  means starting each low-level recorder on its own connection/port.
- **Disk usage.** `.octorec` is uncompressed; bound session length and encode/
  delete when done. (~hundreds of KB/s for a full installation at 60 fps.)
- **Frame de-dup window** is 5 ms; two genuinely-distinct identical frames closer
  than that would be collapsed (visually irrelevant — timing is preserved).
- **The mixed layout is a horizontal strip** (unrolled circle). A true ring
  layout would be a rendering change in `Encoder`/`RadarEncoder`.

---

## Possible next steps

- A combined overlay clip (radar scope composited beside/over `mixed.mp4`) as a
  single deliverable.
- An HTTP/object-storage `Sink` implementation.
- A player that streams a session back into the simulator.
