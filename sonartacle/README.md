# Multi Channel Sampler

A simple audio player for playing samples on specified output channels asynchronously.

## Build

### Prerequisites

#### MacOS

- cmake v3.26
- c++17
- ninja

### How to build

- clone the repo `https://github.com/gueldenstone/MultiChannelSampler.git`
- configure cmake `make -B build -S . -G"Ninja Multi-Config"`
- build `cmake --build build --config Release`
- you can find the binary inside the `build` folder
