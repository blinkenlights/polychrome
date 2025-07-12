defmodule Octopus.Installation.Nation2025Test do
  use Octopus.Installation,
    arrangement: :linear,
    num_panels: 7,
    num_buttons: 7,
    num_joysticks: 0,
    panel_width: 8,
    panel_height: 8,
    panel_gap: 10,
    simulator_layouts: [
      [
        name: "Nation 2025 Test",
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
