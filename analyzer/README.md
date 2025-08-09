## Audio Analyzer

Real-time 3-band analyzer that splits the input into low/mid/high bands, computes smoothed RMS per band, and streams the values over UDP as Protocol Buffers to a remote host. Built as a JUCE Standalone app (product name: "polychrome analyzer").

### How it works

- Uses a JUCE `AudioProcessorGraph` with three band-pass filters (low, mid, high)
- Computes per-band RMS each block and smooths it
- Sends a `SoundToLightControlEvent` wrapped in a `Packet` protobuf over UDP at ~60 Hz
- Exposes parameters for band crossover frequencies and per-band "Listen" toggles; a generic editor lets you tweak them

### How to build

Prerequisites:
- CMake ≥ 3.22, a C++20 compiler
- Protocol Buffers (protoc)
- Linux only: ALSA dev headers and CURL

Commands:

```
cmake -B build -DCMAKE_BUILD_TYPE=Release -DCMAKE_POLICY_VERSION_MINIMUM=3.5
cmake --build build -j 8
```
