defmodule Octopus.Installation.Camp2023 do
  use Octopus.Installation,
    arrangement: :linear,
    num_panels: 10,
    num_buttons: 10,
    num_joysticks: 0,
    panel_width: 8,
    panel_height: 8,
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
