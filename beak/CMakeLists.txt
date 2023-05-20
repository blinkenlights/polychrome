cmake_minimum_required(VERSION 3.22)
set(CMAKE_CXX_STANDARD 20)
set(TARGET_NAME beak)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

project(${TARGET_NAME} VERSION 0.0.1)

set(PROTOCOL_BUFFER_FILES
  "${CMAKE_CURRENT_LIST_DIR}/../protobuf/nanopb.proto"
  "${CMAKE_CURRENT_LIST_DIR}/../protobuf/schema.proto"
)
set(PROTOCOL_BUFFER_FOLDER
  "${CMAKE_CURRENT_LIST_DIR}/../protobuf"
)

# --------------------- go ---------------------------- #
# compile protobufs
file(GLOB_RECURSE GO_SRCS CONFIGURE_DEPENDS *.go)

set(GO_BIN_NAME protobuf-sim)

add_custom_command(OUTPUT ${GO_BIN_NAME}-proto
  DEPENDS ${PROTOCOL_BUFFERS_FILES}
  WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
  COMMAND protoc -I=${PROTOCOL_BUFFER_FOLDER} --go_opt=Mschema.proto=./cmd --go_opt=Mnanopb.proto=./cmd --go_out=test ${PROTOCOL_BUFFER_FILES}
  COMMENT "Generating protobufs for golang"
)
message(STATUS "Golang sources: " ${GO_SRCS})

add_custom_command(OUTPUT ${GO_BIN_NAME}
  DEPENDS ${GO_SRCS} ${GO_BIN_NAME}-proto
  WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/test
  COMMAND go build -o "${CMAKE_CURRENT_BINARY_DIR}/${GO_BIN_NAME}" .
  COMMENT "Building Test App with go"
)

# Add a custom target for the library.
add_custom_target(test-app DEPENDS ${GO_BIN_NAME})

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

# asio
# from https://github.com/cpm-cmake/CPM.cmake/blob/master/examples/asio-standalone/CMakeLists.txt
CPMAddPackage("gh:chriskohlhoff/asio#asio-1-28-0@1.28.0")

# protobuf
find_package(Protobuf REQUIRED)
include_directories(SYSTEM ${Protobuf_INCLUDE_DIRS})
include_directories(SYSTEM ${CMAKE_CURRENT_BINARY_DIR})
protobuf_generate_cpp(PROTO_SRCS PROTO_HDRS ../protobuf/schema.proto ../protobuf/nanopb.proto)

if(asio_ADDED)
  add_library(asio INTERFACE)

  target_include_directories(asio SYSTEM INTERFACE ${asio_SOURCE_DIR}/asio/include)

  target_compile_definitions(asio INTERFACE ASIO_STANDALONE ASIO_NO_DEPRECATED)

  target_link_libraries(asio INTERFACE Threads::Threads)
endif()

# include JUCE framework
set(DONT_SET_USING_JUCE_NAMESPACE ON)
CPMAddPackage("gh:juce-framework/JUCE#7.0.5@7.0.5")
juce_add_console_app(${TARGET_NAME}
  PRODUCT_NAME "beak"
  NEEDS_CURL TRUE
)

juce_generate_juce_header(${TARGET_NAME})

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
      WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
      COMMENT "Generating API documentation with Doxygen"
      VERBATIM)
  else(DOXYGEN_FOUND)
    message("Doxygen need to be installed to generate the doxygen documentation")
  endif(DOXYGEN_FOUND)
endif(BUILD_DOC)

target_sources(${TARGET_NAME}
  PRIVATE
  src/main.cpp
  src/processor.cpp
  src/app.cpp
  src/server.cpp
  src/engine.cpp
  src/resource.cpp
)
target_sources(${TARGET_NAME}
  PRIVATE
  ${PROTO_SRCS}
  ${PROTO_HDRS}
)

target_include_directories(${TARGET_NAME}
  PRIVATE
  src
)

target_compile_options(${TARGET_NAME}
  PRIVATE
  -Werror -Wall -Wextra
)

target_compile_definitions(${TARGET_NAME}
  PRIVATE
  JUCE_WEB_BROWSER=0
  JUCE_USE_CURL=1
  DONT_SET_USING_JUCE_NAMESPACE=0
  cxx_std_17
)

# link juce
target_link_libraries(${TARGET_NAME}
  PRIVATE
  juce::juce_core
  juce::juce_audio_devices
  juce::juce_audio_formats
  juce::juce_audio_basics
  juce::juce_audio_utils
  juce::juce_dsp
  juce::juce_recommended_config_flags
)

# link asio
target_link_libraries(${TARGET_NAME}
  PRIVATE
  asio
)

target_link_libraries(${TARGET_NAME}
  PRIVATE
  ${Protobuf_LIBRARIES}
)

if(UNIX AND NOT APPLE)
  target_link_libraries(${TARGET_NAME}
    PRIVATE
    ${ALSA_LIBRARIES}
  )
endif()
