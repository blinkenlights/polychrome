#!/usr/bin/env bash
sonatacle-proto-sim/sonartacle-proto-sim send playMessage -f /Users/lukas/dev/letterbox/sonartacle/resources/shaker.wav -c 1
for i in {1..10}
do
  sonatacle-proto-sim/sonartacle-proto-sim send playMessage -f https://github.com/gueldenstone/MultiChannelSampler/raw/main/resources/arcade-notification.wav -c $(expr $i % 2 + 1)
  sleep 0.2
done

