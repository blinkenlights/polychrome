defmodule Octopus.Installation.Woodstock2 do
  use Octopus.Installation,
    arrangement: :linear,
    panels: [
      [controller: :polychrome_panel_9, wiring: :serpentine_vertical_bottom_left],
      [controller: :polychrome_panel_10, wiring: :serpentine_vertical_bottom_left]
    ],
    panel_layout: {2, 32},
    num_buttons: 0,
    num_joysticks: 0,
    panel_gap: 32,
    global_speed: 1.0,
    location: :auto,
    auto_brightness: false,
    network_config: [
      mode: :broadcast,
      broadcast_ip: :auto,
      send_in_dev: true
    ],
    simulator_layouts: [
      [
        name: "Woodstock 2",
        mode: "generic",
        pixel_size: {16, 16}
      ]
    ]
end
