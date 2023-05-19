#!/usr/bin/env bash

TEST_APP=./sonartacle-proto-sim

CMD="${TEST_APP} send playMessage"

$CMD -f https://github.com/gueldenstone/MultiChannelSampler/raw/main/resources/pew.wav -c 1
sleep 0.1
$CMD -f https://github.com/gueldenstone/MultiChannelSampler/raw/main/resources/pew.wav -c 2
sleep 0.1
$CMD -f https://github.com/gueldenstone/MultiChannelSampler/raw/main/resources/pew.wav -c 3
sleep 0.1
$CMD -f https://github.com/gueldenstone/MultiChannelSampler/raw/main/resources/pew.wav -c 4
sleep 0.1
$CMD -f https://github.com/gueldenstone/MultiChannelSampler/raw/main/resources/pew.wav -c 5
sleep 0.1
$CMD -f https://github.com/gueldenstone/MultiChannelSampler/raw/main/resources/pew.wav -c 6
sleep 0.1
$CMD -f https://github.com/gueldenstone/MultiChannelSampler/raw/main/resources/pew.wav -c 7
sleep 0.1
$CMD -f https://github.com/gueldenstone/MultiChannelSampler/raw/main/resources/pew.wav -c 8
sleep 0.1
$CMD -f https://github.com/gueldenstone/MultiChannelSampler/raw/main/resources/pew.wav -c 9
sleep 0.1
$CMD -f https://github.com/gueldenstone/MultiChannelSampler/raw/main/resources/pew.wav -c 10
sleep 0.1
