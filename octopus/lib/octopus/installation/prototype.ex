defmodule Octopus.Installation.Prototype do
  use Octopus.Installation,
    arrangement: :linear,
    num_panels: 1,
    num_buttons: 1,
    num_joysticks: 0,
    panel_width: 8,
    panel_height: 8,
    panel_gap: 0,
    global_speed: 0.3,
    network_config: [
      mode: :individual,
      panel_ips: ["blinkenleds-prototype.local"],
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
