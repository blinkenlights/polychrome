#!/usr/bin/env bash

protoc \
  -I=../../../protobuf \
  --go_opt=Mschema.proto=./cmd \
  --go_opt=Mnanopb.proto=./cmd \
  --go_out=. \
  ../../../protobuf/schema.proto ../../../protobuf/nanopb.proto
