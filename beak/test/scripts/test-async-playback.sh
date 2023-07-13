#!/usr/bin/env bash

APP=${APP:-"./build/protobuf-sim"}
if [ -x $APP ]; then
  $APP send playMessage -f file://Users/lukas/dev/polychrome/beak/resources/shaker.wav -c 1
  for i in {1..10}; do
    $APP send playMessage -f https://github.com/gueldenstone/MultiChannelSampler/raw/main/resources/arcade-notification.wav -c $(expr $i % 2 + 1)
    sleep 0.2
  done
else
  echo "${APP} is not executable"
  exit 1
fi
