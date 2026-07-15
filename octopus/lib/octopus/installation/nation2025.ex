defmodule Octopus.Installation.Nation2025 do
  use Octopus.Installation,
    arrangement: :circular,
    circular: [
      ring_radius_m: 10.0,
      panel_bottom_m: 0.4
    ],
    panel_type: :polychrome,
    panels: [
      [controller: :polychrome_01, wiring: :serpentine_horizontal_bottom_left],
      [controller: :polychrome_02, wiring: :serpentine_horizontal_bottom_left],
      [controller: :polychrome_03, wiring: :serpentine_horizontal_bottom_left],
      [controller: :polychrome_04, wiring: :serpentine_horizontal_bottom_left],
      [controller: :polychrome_05, wiring: :serpentine_horizontal_bottom_left],
      [controller: :polychrome_06, wiring: :serpentine_horizontal_bottom_left],
      [controller: :polychrome_07, wiring: :serpentine_horizontal_bottom_left],
      [controller: :polychrome_08, wiring: :serpentine_horizontal_bottom_left],
      [controller: :polychrome_09, wiring: :serpentine_horizontal_bottom_left],
      [controller: :polychrome_10, wiring: :serpentine_horizontal_bottom_left],
      [controller: :polychrome_11, wiring: :serpentine_horizontal_bottom_left],
      [controller: :polychrome_12, wiring: :serpentine_horizontal_bottom_left]
    ],
    panel_layout: {8, 8},
    num_buttons: 12,
    num_joysticks: 0,
    panel_gap: 18,
    global_speed: 0.8,
    location: {52.684273, 12.959300},
    auto_brightness: false,
    network_config: [
      mode: :broadcast,
      broadcast_ip: :auto,
      send_in_dev: false
    ],
    simulator_layouts: [
      [
        name: "Generic Development View",
        mode: "generic",
        pixel_size: {12, 12}
      ],
      [
        name: "Nation 2025",
        mode: "image",
        background_image: "/images/nation2025-background.webp",
        pixel_image: "/images/nation2025-overlay.webp",
        image_size: {3463, 1469},
        pixel_size: {8, 8},
        offset_x: 600,
        offset_y: 1100,
        spacing: 128
      ]
    ]
end
