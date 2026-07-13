defmodule Octopus.Installation.Nation2026 do
  use Octopus.Installation,
    arrangement: :circular,
    ring_radius_m: 10.0,
    panel_type: :polychrome,
    panels: [
      [controller: :polychrome_panel_1, wiring: :serpentine_horizontal_bottom_left],
      [controller: :polychrome_panel_2, wiring: :serpentine_horizontal_bottom_left],
      [controller: :polychrome_panel_3, wiring: :serpentine_horizontal_bottom_left],
      [controller: :polychrome_panel_4, wiring: :serpentine_horizontal_bottom_left],
      [controller: :polychrome_panel_5, wiring: :serpentine_horizontal_bottom_left],
      [controller: :polychrome_panel_6, wiring: :serpentine_horizontal_bottom_left],
      [controller: :polychrome_panel_7, wiring: :serpentine_horizontal_bottom_left],
      [controller: :polychrome_panel_8, wiring: :serpentine_horizontal_bottom_left],
      [controller: :polychrome_panel_9, wiring: :serpentine_horizontal_bottom_left],
      [controller: :polychrome_panel_10, wiring: :serpentine_horizontal_bottom_left],
      [controller: :polychrome_panel_11, wiring: :serpentine_horizontal_bottom_left],
      [controller: :polychrome_panel_12, wiring: :serpentine_horizontal_bottom_left]
    ],
    panel_layout: {8, 8},
    num_buttons: 0,
    num_joysticks: 0,
    panel_gap: 18,
    global_speed: 1.0,
    location: {52.684273, 12.959300},
    auto_brightness: false,
    radar_enabled: true,
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
        name: "Nation 2026",
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
