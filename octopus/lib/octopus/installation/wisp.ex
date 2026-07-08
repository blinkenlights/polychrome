defmodule Octopus.Installation.Wisp do
  use Octopus.Installation,
    arrangement: :linear,
    panels: [
      [controller: :polychrome_panel_prototype, wiring: :linear_strip_24_vertical]
    ],
    panel_layout: {1, 24},
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
        name: "Wisp",
        mode: "generic",
        pixel_size: {32, 32}
      ]
    ]
end
