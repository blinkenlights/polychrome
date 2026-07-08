defmodule Octopus.Installation.Nation2024 do
  use Octopus.Installation,
    arrangement: :linear,
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
      [controller: :polychrome_panel_10, wiring: :serpentine_horizontal_bottom_left]
    ],
    panel_layout: {8, 8},
    num_buttons: 10,
    num_joysticks: 0,
    panel_gap: 17,
    global_speed: 1.0,
    location: {52.684273, 12.959300},
    auto_brightness: false,
    network_config: [
      mode: :broadcast,
      broadcast_ip: :auto,
      send_in_dev: false
    ],
    simulator_layouts: [
      [
        name: "Nation 2024",
        background_image: "/images/nation.webp",
        pixel_image: "/images/mildenberg-pixel-overlay.webp",
        image_size: {12_900, 5470},
        pixel_size: {25, 25},
        offset_x: 1750,
        offset_y: 3750,
        spacing: 800
      ]
    ]
end
