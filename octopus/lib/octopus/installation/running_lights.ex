defmodule Octopus.Installation.RunningLights do
  use Octopus.Installation,
    arrangement: :linear,
    panels: [:polychrome_panel_prototype],
    panel_layout: {64, 1},
    num_buttons: 1,
    num_joysticks: 0,
    panel_gap: 0,
    global_speed: 1.0,
    radar_enabled: false,
    location: :auto,
    auto_brightness: false,
    network_config: [
      mode: :individual,
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
