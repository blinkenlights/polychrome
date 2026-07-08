defmodule Octopus.Installation.Pixie do
  use Octopus.Installation,
    arrangement: :linear,
    panels: [
      [controller: :polychrome_panel_prototype, wiring: :serpentine_vertical_bottom_left]
    ],
    panel_layout: {8, 8},
    num_buttons: 1,
    num_joysticks: 0,
    panel_gap: 0,
    global_speed: 0.3,
    radar_enabled: false,
    location: :auto,
    auto_brightness: false,
    network_config: [
      mode: :individual,
      send_in_dev: true
    ],
    simulator_layouts: [
      [
        name: "Pixie",
        mode: "generic",
        pixel_size: {64, 64}
      ]
    ]
end
