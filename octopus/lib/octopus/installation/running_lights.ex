defmodule Octopus.Installation.RunningLights do
  use Octopus.Installation,
    arrangement: :linear,
    num_panels: 1,
    num_buttons: 1,
    num_joysticks: 0,
    panel_width: 64,
    panel_height: 1,
    panel_gap: 0,
    global_speed: 0.3,
    location: :auto,
    auto_brightness: false,
    network_config: [
      mode: :individual,
      panels: [
        [address: "blinkenleds-prototype.local", panel_index: 1]
      ],
      send_in_dev: true
    ],
    simulator_layouts: [
      [
        name: "Running Lights",
        mode: "generic",
        pixel_size: {16, 16}
      ]
    ]
end
