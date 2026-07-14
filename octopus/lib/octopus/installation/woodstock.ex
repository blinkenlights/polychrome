defmodule Octopus.Installation.Woodstock do
  use Octopus.Installation,
    arrangement: :linear,
    panels: [
      [controller: :pixie, port: 2, wiring: :serpentine_vertical_bottom_left]
    ],
    panel_layout: {2, 32},
    num_buttons: 0,
    num_joysticks: 0,
    panel_gap: 0,
    global_speed: 1.0,
    location: :auto,
    auto_brightness: false,
    network_config: [
      mode: :individual,
      send_in_dev: true
    ],
    simulator_layouts: [
      [
        name: "Woodstock",
        mode: "generic",
        pixel_size: {16, 16}
      ]
    ]
end
