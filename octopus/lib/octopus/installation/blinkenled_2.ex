defmodule Octopus.Installation.Blinkenled2 do
  use Octopus.Installation,
    arrangement: :linear,
    num_panels: 1,
    num_buttons: 1,
    num_joysticks: 0,
    panel_width: 8,
    panel_height: 8,
    panel_gap: 0,
    global_speed: 0.3,
    location: :auto,
    auto_brightness: false,
    network_config: [
      mode: :individual,
      panels: [
        [address: "blinkenleds-2.local", panel_index: 2]
      ],
      send_in_dev: true
    ],
    simulator_layouts: [
      [
        name: "Blinkenled 2",
        mode: "generic",
        pixel_size: {64, 64}
      ]
    ]
end
