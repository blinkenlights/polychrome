# Recording & Playback — User Guide

This guide explains how to record what Octopus sends to the LED panels (and,
optionally, the radar sensor tracking data) and how to turn those recordings
into playable video.

For the *why* and the internal design, see
[`recording_architecture.md`](./recording_architecture.md).

---

## What you can record

| Stream | Source | On-disk file | Becomes |
|--------|--------|--------------|---------|
| Panels (animations) | The mixer's outgoing frames | `panels.octorec` | one video per panel + a mixed video |
| Radar (motion) | Radar sensor tracks | `radar.jsonl` | a top-down "scope" video |

A **session** records both together into one timestamped directory using a
shared clock, so the panel video and the radar scope line up frame-for-frame.

```
recordings/
  session-20260712-143000/
    panels.octorec
    radar.jsonl
```

Recording is **disabled by default** and has zero overhead until you turn it
on. It is designed so it can never crash or slow down the running installation
(see the architecture doc for the guarantees).

---

## Configuration

`config/config.exs`:

```elixir
config :octopus, Octopus.Recording,
  enabled: false,          # auto-start a session on boot
  output_dir: "recordings",# base directory for sessions/files
  max_queue: 600,          # mailbox backlog before frames are dropped
  sink: {:file, []}        # default sink (see "Streaming to a remote server")
```

- `enabled: true` makes the app start a recording session automatically at
  boot. Leave it `false` for on-demand recording.
- `output_dir` is relative to the app's working directory unless absolute.
- `max_queue` is a safety valve: if writing can't keep up (slow disk / slow
  network) the recorder drops frames instead of growing memory. Dropped frames
  just extend the previous frame's on-screen duration in playback.

---

## Recording (runtime control)

From an `iex` session attached to the app:

```elixir
# Start a session (panels + radar-if-enabled) into output_dir/session-<stamp>/
Octopus.Recording.start()
# => {:ok, %{dir: "recordings/session-...", panels: "file:...", radar: "file:..."}}

# Start into a specific base directory
Octopus.Recording.start(dir: "/tmp/rec")

# Panels only (skip radar even if radar is enabled)
Octopus.Recording.start(radar: false)

# Inspect status
Octopus.Recording.status()
# => %{active: true, dir: "...", panels: %{active: true, written: 1234, dropped: 0, ...},
#      radar: %{active: true, written: 88, dropped: 0, ...}}

Octopus.Recording.recording?()   # => true / false

# Stop (flushes and closes both files)
Octopus.Recording.stop()
```

Notes:

- `start/1` returns `{:error, :already_recording}` if a session is already
  active. Call `stop/0` first.
- Radar is only recorded when `Octopus.Radar.enabled?()` is true (you can force
  it off with `radar: false`). If radar is off, only `panels.octorec` is
  written.
- `stop/0` is synchronous: once it returns, all frames received before it are
  guaranteed to be written and the files are closed.

### Recording a single stream (advanced)

The session always writes files. If you want just one stream (e.g. only panels,
or to a custom sink), drive the low-level recorders directly:

```elixir
Octopus.Recording.PanelRecorder.start_recording(dir: "/tmp/rec")
Octopus.Recording.PanelRecorder.stop_recording()

Octopus.Recording.RadarRecorder.start_recording(dir: "/tmp/rec")
Octopus.Recording.RadarRecorder.stop_recording()
```

---

## Streaming to a remote server

Instead of (or before) writing to disk, a stream can be sent to a TCP server.
The exact same bytes that would go into a file are sent over the socket, so the
receiver can just append them to a `.octorec` / `.jsonl` file and encode later.

Start a single recorder with the remote sink:

```elixir
Octopus.Recording.PanelRecorder.start_recording(
  sink_mod: Octopus.Recording.Sink.Remote,
  sink_opts: [host: "10.0.0.5", port: 7000]
)
```

Remote sink options: `:host` (string / charlist / IP tuple), `:port`,
`:connect_timeout` (default 5000 ms), `:send_timeout` (default 2000 ms).

On the server, capture the stream to a file, then encode it:

```sh
# netcat
nc -l 7000 > session.octorec

# or socat (append-safe)
socat TCP-LISTEN:7000,reuseaddr OPEN:session.octorec,creat,append

mix octopus.recording.encode session.octorec
```

> The **session** API (`Octopus.Recording.start/1`) always uses file sinks,
> because both streams share one directory. Remote streaming is a per-recorder
> feature (one stream = one connection). To stream both panels and radar,
> start each recorder on its own port.

---

## Encoding to video

Encoding is an **offline** step (a mix task) that shells out to `ffmpeg`. It
never runs inside the live app, so it can't affect the installation.

Requires `ffmpeg` on your `PATH`:

- macOS: `brew install ffmpeg`
- Debian/Ubuntu: `apt install ffmpeg`

### Encode a whole session

```sh
mix octopus.recording.encode recordings/session-20260712-143000
```

Produces, inside the session directory:

- `panel_00.mp4 … panel_NN.mp4` — one video per panel (native resolution,
  upscaled with crisp nearest-neighbour pixels)
- `mixed.mp4` — all panels side by side in panel order (the circular
  installation "unrolled" into a horizontal strip)
- `radar.mp4` — the top-down radar scope

### Encode a single file

```sh
mix octopus.recording.encode recordings/panels-20260712-143000.octorec
mix octopus.recording.encode recordings/radar-20260712-143000.jsonl
```

### Options

| Option | Applies to | Default | Meaning |
|--------|-----------|---------|---------|
| `--out DIR` | all | dir named after the file (session: the session dir) | output directory |
| `--fps N` | all | `30` | constant output frame rate |
| `--scale N` | panels | `16` | integer nearest-neighbour upscale factor |
| `--size N` | radar | `256` | square scope size in pixels |
| `--no-panels` | panels | — | skip per-panel videos |
| `--no-mixed` | panels | — | skip the mixed video |
| `--ffmpeg PATH` | all | `ffmpeg` | ffmpeg executable |

Examples:

```sh
mix octopus.recording.encode rec.octorec --fps 60 --scale 24 --out /tmp/out
mix octopus.recording.encode rec.octorec --no-panels          # mixed only
mix octopus.recording.encode session-dir --size 512           # bigger radar scope
```

Because both encoders resample to the same `--fps`, the `mixed.mp4` and
`radar.mp4` from one session have the same frame count and duration and can be
played/overlaid in sync.

---

## Typical workflows

**Local capture → video**

```elixir
Octopus.Recording.start()
# ... let the animation run ...
Octopus.Recording.stop()   # note the returned dir
```
```sh
mix octopus.recording.encode recordings/session-<stamp>
```

**Remote capture → video (on the server)**

```elixir
Octopus.Recording.PanelRecorder.start_recording(
  sink_mod: Octopus.Recording.Sink.Remote, sink_opts: [host: "server", port: 7000])
```
```sh
nc -l 7000 > capture.octorec        # on the server
mix octopus.recording.encode capture.octorec
```

**Always-on recording in production**

```elixir
config :octopus, Octopus.Recording, enabled: true
```
A session auto-starts at boot; find it under `output_dir/session-<stamp>/`.

---

## Storage sizing

The panel recording (`.octorec`) writes a **fixed-size record per frame**:

```
bytes/frame = 4 (timestamp) + num_panels × panel_width × panel_height × 3 (RGB)
```

For the current installation (12 panels of 8×8) that is:

```
4 + 12 × 8 × 8 × 3 = 4 + 2304 = 2308 bytes/frame
```

(The 26-byte header is one-time and negligible. Grayscale `WFrame`s are stored
as RGB, so they cost the same.)

Size scales linearly with the frame rate the mixer actually emits — which is
**event-driven, up to ~60 fps**, not fixed:

```
MB/hour = bytes/frame × fps × 3600 ÷ 1,000,000
```

| Frame rate | Per second | Per hour (MB) | Per hour (MiB) |
|-----------|-----------|---------------|----------------|
| 60 fps (peak) | ~135 KiB/s | ≈ 499 MB | ≈ 475 MiB |
| 30 fps | ~68 KiB/s | ≈ 249 MB | ≈ 238 MiB |
| 24 fps | ~54 KiB/s | ≈ 199 MB | ≈ 190 MiB |
| 10 fps | ~23 KiB/s | ≈ 83 MB | ≈ 79 MiB |
| ~1 fps (idle) | ~2.3 KiB/s | ≈ 8 MB | ≈ 8 MiB |

Plan for roughly **0.5 GB/hour at full 60 fps**, ~250 MB/hour at 30 fps, and much
less when animations are mostly static (the mixer emits only ~1 idle frame per
second when nothing changes, and de-duplicated split-part frames don't count).

Notes:

- This is the **uncompressed on-disk `.octorec`** size — what you budget disk for
  *during* recording. The encoded MP4s are far smaller.
- **Radar (`radar.jsonl`) is tiny** by comparison: a few hundred bytes per frame
  at a handful of frames/second — on the order of a few MB/hour.
- Rule of thumb for other geometries:
  `(4 + panels × w × h × 3) × fps × 3600` bytes per hour.
- If you run always-on (`enabled: true`), size the disk for the peak rate ×
  expected session length, or rotate/encode/delete sessions.

---

## Compression

Recordings can be gzip-compressed on the fly to save disk (and network) space.
Compression uses Erlang's built-in `:zlib`, so there are **no native
dependencies** — it works on a Raspberry Pi out of the box.

Enable it globally:

```elixir
config :octopus, Octopus.Recording,
  compress: true,
  gzip_level: 6   # 0..9; lower = faster / less CPU
```

Or per recording:

```elixir
Octopus.Recording.start(dir: "/tmp/rec", compress: true)
```

When enabled:

- File targets gain a `.gz` suffix (e.g. `panels-<stamp>.octorec.gz`).
- The remote sink streams gzip bytes too (compose transparently).
- The encoder reads `.gz` recordings automatically — no extra flags:

  ```sh
  mix octopus.recording.encode recordings/panels-20260712-143000.octorec.gz
  ```

- Standard gzip, so `gunzip`/`zcat` work on the files as well.

### How much it saves

Highly content-dependent (see the measured numbers in
[`recording_architecture.md`](./recording_architecture.md#compression)):

| Content | Typical result |
|---------|----------------|
| Busy full-colour animation | ~1.3× smaller (~20–35%) |
| Normal scenes (motion + dark areas) | ~2–5× smaller |
| Text / sparse / mostly dark | 10× – 1000× smaller |
| Full-frame random noise (unrealistic) | ~1× (no gain) |

### Raspberry Pi notes

- CPU cost is small next to the ~135 KiB/s data rate; if the Pi is busy, lower
  `gzip_level` (e.g. `1`–`4`) for cheaper compression at a slightly worse ratio.
- No cross-compiled dependencies are involved (`:zlib` ships with OTP).
- A gzip stream is only finalized when the recording is **stopped**; the sink
  also flushes periodically so a hard power-loss loses at most a few seconds.
  Always `stop/0` cleanly when you can.

---

## Troubleshooting

- **`ffmpeg was not found`** — install ffmpeg or pass `--ffmpeg /path/to/ffmpeg`.
- **`Recording contains no frames`** — nothing was recorded (e.g. the app wasn't
  producing frames, or radar wasn't enabled for `radar.jsonl`).
- **`status` shows `dropped > 0`** — the sink couldn't keep up (slow disk or slow
  remote). Lower the frame rate at the source or check the sink; the recording
  is still valid, just missing some frames.
- **`radar.jsonl` is empty / only metadata** — radar wasn't enabled
  (`Octopus.Radar.enabled?()` was false) or no targets were tracked.
- **Disk usage** — panel frames are uncompressed until encoded (~0.5 GB/hour at
  60 fps for a 12×8×8 installation). Enable [Compression](#compression) to cut
  this substantially, and see [Storage sizing](#storage-sizing). Keep sessions
  bounded and encode/delete when done.
- **`Could not decompress ...`** — a `.gz` recording is truncated (e.g. the app
  was hard-killed before `stop/0`) or isn't actually gzip.

---

## File layout reference

```
recordings/
  session-<YYYYMMDD-HHMMSS>/
    panels.octorec      # binary panel frames (see architecture doc)
    radar.jsonl         # one JSON object per radar frame
    # after encoding:
    panel_00.mp4 ...    # one per panel
    mixed.mp4           # all panels, side by side
    radar.mp4           # top-down scope
```

Standalone (low-level recorder) files are named
`panels-<stamp>.octorec` and `radar-<stamp>.jsonl` in `output_dir`.
