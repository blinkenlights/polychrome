defmodule Octopus.Installation.Nation2024 do
  use Octopus.Installation,
    arrangement: :linear,
    num_panels: 10,
    num_buttons: 10,
    num_joysticks: 0,
    panel_width: 8,
    panel_height: 8,
    panel_gap: 17,
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
        image_size: {12900, 5470},
        pixel_size: {25, 25},
        offset_x: 1750,
        offset_y: 3750,
        spacing: 800
      ]
    ]
end
