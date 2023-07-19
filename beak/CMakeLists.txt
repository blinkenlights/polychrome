cmake_minimum_required(VERSION 3.22)
set(CMAKE_CXX_STANDARD 20)
set(TARGET_NAME beak)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
set(CMAKE_BUILD_TYPE Debug)

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
  src/processor.cpp
  src/app.cpp
  src/server.cpp
  src/engine.cpp
  src/resource.cpp
  src/simEngine.cpp
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

juce_add_console_app(${TARGET_NAME}
  PRODUCT_NAME "beak"
  NEEDS_CURL TRUE
  CATCH_UNHANDLED_EXCEPTIONS TRUE
)

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
  DONT_SET_USING_JUCE_NAMESPACE=0
  cxx_std_17
)

target_compile_options(${TARGET_NAME}
  PRIVATE
  -Werror -Wall -Wextra
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

# doxygen
find_package(Doxygen)

if(BUILD_DOC)
  if(DOXYGEN_FOUND)
    # set input and output files
    set(DOXYGEN_FILE ${CMAKE_CURRENT_SOURCE_DIR}/Doxyfile)
    message("Doxygen build started")

    # note the option ALL which allows to build the docs together with the application
    add_custom_target(doc_doxygen ALL
      COMMAND ${DOXYGEN_EXECUTABLE} ${DOXYGEN_FILE}
      WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/docs
      COMMENT "Generating API documentation with Doxygen"
      VERBATIM)
  else(DOXYGEN_FOUND)
    message("Doxygen need to be installed to generate the doxygen documentation")
  endif(DOXYGEN_FOUND)
endif(BUILD_DOC)
