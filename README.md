# Letterbox
Blinkenlights Letterbox light installation in Mildenberg, Germany.

## Components

| Name | Description | Documentation |
| ---- | ------------| ------------- |
| octopus | Central hub for the project. <br/>Manages apps, mixes pixel streams, shows previews. | [Readme](./octopus/README.md)
| protobuf | Protobuf schema files for the data packets | [schema.proto](./protobuf/schema.proto)
| blinkenleds | ESP32 firmware that drives the LED panels | [Readme](./blinkenleds/README.md)
| calibration | Tooling to create color calibration tables for the Leds | [Readme](./calibration/README.md)
| beak | Audio engine that drives the sound output | todo

## Architecture

Protobuf is used everywhere as the wire format. All messages are wrapped in the `Packet` message to ensure save decoding. See the [schema](./protobuf/schema.proto) for more details.

### Data flow for pixel and sound outputs

```mermaid 
flowchart LR
  external_1[External Source] --> |UDP| udp_server_1
  external_2[External Source] --> |UDP| udp_server_2

  subgraph Octopus
  
  udp_server_1["Octopus.UDPServer [Port 2342]"] --> mixer
  udp_server_2["Octopus.UDPServer [Port 2343]"] --> mixer

  app_1[Octopus.Apps.Foo] --> mixer
  app_2[Octopus.Apps.Baa] --> mixer

  mixer["Octopus.Mixer"]-->broadcast[Octopus.Broadcaster]
  mixer --> |pubsub| manager[OctobusWeb.ManagerLive]

  end

  subgraph "Blinkenled panel (10x)"
  broadcast-->|UDP Broadcast|esp32[ESP32]
  esp32-->LEDS
  end

  broadcast --> |UDP Broadcast| sim
  sim[Simulator]-->|live_view| live[HTML]

  subgraph "Beak (sound)"
  broadcast --> |UDP Broadcast| beak
  beak--> Speakers
  end
```


### Data flow for input events


```mermaid 
---
title: "Input events"
---
flowchart LR

  controllers --> |UDP| input_adapter

  subgraph Octopus
  
  input_adapter[Octopus.InputAdapter] --> mixer["Octopus.Mixer"]
  manager[OctobusWeb.ManagerLive] --> mixer


  mixer --> udp_server_1["Octopus.UDPServer [Port 2342]"]
  mixer --> udp_server_2["Octopus.UDPServer [Port 2343]"]
  mixer --> app_1[Octopus.Apps.Foo]
  mixer --> app_2[Octopus.Apps.Baa]

  end

  udp_server_1 --> |UDP| external_1[External Source]
  udp_server_2 --> |UDP| external_2[External Source]
```
