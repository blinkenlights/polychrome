defmodule Octopus.Installation.Prototype do
  use Octopus.Installation,
    arrangement: :linear,
    num_panels: 1,
    num_buttons: 1,
    num_joysticks: 0,
    panel_width: 8,
    panel_height: 8,
    panel_gap: 1,
    simulator_layouts: [
      [
        name: "Prototype",
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
