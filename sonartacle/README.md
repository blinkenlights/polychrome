# Multi Channel Sampler

A simple audio player for playing samples on specified output channels asynchronously.

## Build

### Prerequisites

#### MacOS

- cmake v3.22
- c++17
- ninja
- protoc
- libcurl
- everything to build juce framework:

### How to build

- hint: this project uses [CPM](https://github.com/cpm-cmake/CPM.cmake) to fetch [juce](https://github.com/juce-framework/JUCE) and [asio](https://github.com/chriskohlhoff/asio). set `export CPM_SOURCE_CACHE=$HOME/.cache/CPM` to avoid refetching after deleting the build folder
- clone the repo `https://github.com/gueldenstone/MultiChannelSampler.git`
- configure cmake `make -B build -S . -G"Ninja Multi-Config"`
- build `cmake --build build`
- you can find the binary inside the `build` folder


## Current status

### What's working?
- Sample playback from local and remote files in mono wav format:
    - `file://path/to/local/file.wav` (must be absolute)
    - `https://myserver.net/file.wav`
- Caching of remote and local files in memory
- Protobuf API to preload samples into cache and trigger playback


### Todo
- Refactor caching:
    - make use of etags (or another mechanism) to check if a locally found file is up to date
    - limit the amount of samples and/or the used memory of the cache

