# letterbox
Blinkenlights Letterbox light installation in Mildenberg, Germany


# Architecture
```mermaid
graph LR
  external_generator_1 --> server
  external_generator_2 --> server
  server[Mixer.UDPServer] --> stream_1
  stream_1[Mixer.PixelStream] -->  mixer 
  
  internal_generators --> stream_2
  stream_2[Mixer.PixelStream] --> mixer 

  mixer[Mixer.Selector]-->broadcast

  broadcast[Mixer.Broadcaster] --> |UDP| sim
  sim[Sim]-->|live_view| live[HTML]

  broadcast-->|UDP|led_controller
```

