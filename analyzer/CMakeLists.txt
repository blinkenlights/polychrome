cmake_minimum_required(VERSION 3.22)
set(CMAKE_CXX_STANDARD 20)
set(TARGET_NAME analyzer)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
set(JUCE_COPY_PLUGIN_AFTER_BUILD 0)

# set(CMAKE_OSX_ARCHITECTURES "x86_64" CACHE INTERNAL "" FORCE)
project(${TARGET_NAME} VERSION 0.0.1)

# --------------------- sources ---------------------------- #
set(PROTOBUF_SRCS
  "${CMAKE_CURRENT_LIST_DIR}/../protobuf/nanopb.proto"
  "${CMAKE_CURRENT_LIST_DIR}/../protobuf/schema.proto"
)

set(PROTOBUF_FOLDER
  "${CMAKE_CURRENT_LIST_DIR}/../protobuf"
)

set(CPP_SRCS
  src/main.cpp
)

# --------------------- c++ ---------------------------- #
# ALSA for Linux (needs to be found up here)
if(UNIX AND NOT APPLE)
  find_package(ALSA REQUIRED)
  find_package(CURL REQUIRED)
endif()

# threads
find_package(Threads REQUIRED)

# cpm
include(cmake/CPM.cmake)

# plog logging framework
CPMAddPackage("gh:SergiusTheBest/plog#1.1.9@1.1.9")

# fmt formatting library
CPMAddPackage("gh:fmtlib/fmt#10.0.0@10.0.0")

# asio
# from https://github.com/cpm-cmake/CPM.cmake/blob/master/examples/asio-standalone/CMakeLists.txt
CPMAddPackage("gh:chriskohlhoff/asio#asio-1-28-0@1.28.0")

if(asio_ADDED)
  add_library(asio INTERFACE)
  target_include_directories(asio SYSTEM INTERFACE ${asio_SOURCE_DIR}/asio/include)
  target_compile_definitions(asio INTERFACE ASIO_STANDALONE ASIO_NO_DEPRECATED)
  target_link_libraries(asio INTERFACE Threads::Threads)
endif()

# protobuf
find_package(Protobuf REQUIRED)
protobuf_generate_cpp(PROTO_SRCS PROTO_HDRS ${PROTOBUF_SRCS})
include_directories(SYSTEM ${Protobuf_INCLUDE_DIRS})
include_directories(SYSTEM ${CMAKE_CURRENT_BINARY_DIR})

# JUCE framework
CPMAddPackage("gh:juce-framework/JUCE#7.0.5@7.0.5")

# juce_add_console_app(${TARGET_NAME}
# PRODUCT_NAME "analyzer"
# CATCH_UNHANDLED_EXCEPTIONS TRUE
# )
juce_add_plugin(${TARGET_NAME}

  # VERSION ...                               # Set this if the plugin version is different to the project version
  # ICON_BIG ...                              # ICON_* arguments specify a path to an image file to use as an icon for the Standalone
  # ICON_SMALL ...

  # IS_SYNTH TRUE/FALSE                       # Is this a synth or an effect?
  # NEEDS_MIDI_INPUT TRUE/FALSE               # Does the plugin need midi input?
  # NEEDS_MIDI_OUTPUT TRUE/FALSE              # Does the plugin need midi output?
  # IS_MIDI_EFFECT TRUE/FALSE                 # Is this plugin a MIDI effect?
  # EDITOR_WANTS_KEYBOARD_FOCUS TRUE/FALSE    # Does the editor need keyboard focus?
  # COPY_PLUGIN_AFTER_BUILD TRUE/FALSE        # Should the plugin be installed to a default location after building?
  COMPANY_NAME blinkenlights # Specify the name of the plugin's author
  PLUGIN_MANUFACTURER_CODE Blnk # A four-character manufacturer id with at least one upper-case character
  PLUGIN_CODE Poly # A unique four-character plugin id with exactly one upper-case character
  NEEDS_CURL TRUE

  # GarageBand 10.3 requires the first letter to be upper-case, and the remaining letters to be lower-case
  FORMATS Standalone # The formats to build. Other valid formats are: AAX Unity VST AU AUv3
  PRODUCT_NAME "polychrome analyzer") # The name of the final executable, which can differ from the target name

juce_generate_juce_header(${TARGET_NAME})

# project sources
target_sources(${TARGET_NAME}
  PRIVATE
  ${CPP_SRCS}
  ${PROTO_SRCS}
  ${PROTO_HDRS}
)

target_compile_definitions(${TARGET_NAME}
  PRIVATE
  JUCE_WEB_BROWSER=0
  JUCE_USE_CURL=1
  JUCE_VST3_CAN_REPLACE_VST2=0
  cxx_std_17
)

target_compile_options(${TARGET_NAME}
  PRIVATE
  -Wall -Wextra
)

# link libs
target_link_libraries(${TARGET_NAME}
  PRIVATE
  plog::plog
  fmt::fmt
  juce::juce_core
  juce::juce_audio_devices
  juce::juce_audio_formats
  juce::juce_audio_basics
  juce::juce_audio_utils
  juce::juce_dsp
  juce::juce_recommended_config_flags
  juce::juce_recommended_lto_flags
  juce::juce_recommended_warning_flags
  asio
  ${Protobuf_LIBRARIES}
)

# linux only alsa
if(UNIX AND NOT APPLE)
  target_link_libraries(${TARGET_NAME}
    PRIVATE
    ${ALSA_LIBRARIES}
  )
endif()

# install
install(TARGETS ${TARGET_NAME} RUNTIME DESTINATION /usr/local/bin/)
