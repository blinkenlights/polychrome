defmodule Octopus.Installation.Camp2023 do
  use Octopus.Installation,
    arrangement: :linear,
    panels: [
      [controller: :polychrome_panel_1, wiring: :serpentine_8x8_bottom_left],
      [controller: :polychrome_panel_2, wiring: :serpentine_8x8_bottom_left],
      [controller: :polychrome_panel_3, wiring: :serpentine_8x8_bottom_left],
      [controller: :polychrome_panel_4, wiring: :serpentine_8x8_bottom_left],
      [controller: :polychrome_panel_5, wiring: :serpentine_8x8_bottom_left],
      [controller: :polychrome_panel_6, wiring: :serpentine_8x8_bottom_left],
      [controller: :polychrome_panel_7, wiring: :serpentine_8x8_bottom_left],
      [controller: :polychrome_panel_8, wiring: :serpentine_8x8_bottom_left],
      [controller: :polychrome_panel_9, wiring: :serpentine_8x8_bottom_left],
      [controller: :polychrome_panel_10, wiring: :serpentine_8x8_bottom_left]
    ],
    panel_layout: {8, 8},
    num_buttons: 10,
    num_joysticks: 0,
    panel_gap: 18,
    global_speed: 1.0,
    location: {53.030246, 13.305036},
    auto_brightness: false,
    network_config: [
      mode: :broadcast,
      broadcast_ip: :auto,
      send_in_dev: false
    ],
    simulator_layouts: [
      [
        name: "Camp 2023",
        background_image: "/images/mildenberg-dark.webp",
        pixel_image: "/images/mildenberg-pixel-overlay.webp",
        image_size: {12_900, 5470},
        pixel_size: {25, 25},
        offset_x: 1750,
        offset_y: 3750,
        spacing: 800
      ]
    ]
end
