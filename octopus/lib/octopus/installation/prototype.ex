defmodule Octopus.Installation.Prototype do
  use Octopus.Installation,
    arrangement: :linear,
    panel_type: :pixie,
    panels: [
      [controller: :pixie, port: 1, wiring: :serpentine_horizontal_bottom_left]
    ],
    panel_layout: {8, 8},
    num_buttons: 1,
    num_joysticks: 0,
    panel_gap: 0,
    global_speed: 0.3,
    location: :auto,
    auto_brightness: false,
    network_config: [
      mode: :individual,
      send_in_dev: true
    ],
    simulator_layouts: [
      [
        name: "Prototype",
        mode: "generic",
        pixel_size: {64, 64}
      ]
    ]
end
