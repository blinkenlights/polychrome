# letterbox
Blinkenlights Letterbox light installation in Mildenberg, Germany


# Architecture
```mermaid
graph LR
  external_generator_1 --> server
  external_generator_2 --> server
  server[Octopus.UDPServer] --> stream_1
  stream_1[Octopus.PixelStream] -->  octopus 
  
  internal_generators --> stream_2
  stream_2[Octopus.PixelStream] --> octopus 

  octopus[Octopus.Selector]-->broadcast

  broadcast-->|UDP|esp32_firmware
  esp32_firmware-->LEDS

  broadcast[Octopus.Broadcaster] --> |UDP| sim
  sim[Sim]-->|live_view| live[HTML]
```

