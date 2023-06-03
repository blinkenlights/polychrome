# Beak

Audio Engine component of letterbox.

## Build

### Prerequisites

- cmake v3.22
- c++20
- ninja
- protoc
- libcurl
- [JUCE Dependencies](https://github.com/juce-framework/JUCE/blob/master/docs/Linux%20Dependencies.md)
- golang (optional)

### Build Steps

All build steps can be carried out by cmake. Commands should be run from `<PATH_TO_REPO>/beak`.

#### Build beak

- hint: this project uses [CPM](https://github.com/cpm-cmake/CPM.cmake) to fetch [juce](https://github.com/juce-framework/JUCE) and [asio](https://github.com/chriskohlhoff/asio). set `export CPM_SOURCE_CACHE=$HOME/.cache/CPM` to avoid refetching after deleting the build folder
- clone the repo `https://github.com/gueldenstone/MultiChannelSampler.git`
- configure cmake (specifying the generator is optional) `cmake -B build -S . -GNinja`
- build `cmake --build build --config Debug`
- you can find the binary here: `build/beak_artefacts/Debug/beak`

#### Build test application

There is a test application build in golang to simply test the UDP protobuf API.

- set the `BUILD_TEST_APP` option to `TRUE`
- `cmake -B build -S . -GNinja -DBUILD_TEST_APP=TRUE`
- for convenience there are test scripts under `test/scripts`

#### Build documentation

The code is documented using doxygen.

- set the `BUILD_DOC` option to `TRUE`
- `cmake -B build -S . -GNinja -DBUILD_DOC=TRUE`
- documentation can be found in `docs`

### Usage

Run beak from the `build/beak_artefacts/Debug`. The following commands with options are available:

#### Run the engine

`./beak run -p <port_numer> -c <absolute_path_to_cache_dir> -d <device name> -o <number_of_output_channels> -i <number_of_input_channels>`.

#### List available devices

`./beak run list-devices`

#### Test playback

`./beak play -f <absolute_path_to_sample.wav> -c <channel_number> -d <device name> -o <number_of_output_channels> -i <number_of_input_channels>`.
