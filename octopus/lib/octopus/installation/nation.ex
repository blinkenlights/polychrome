defmodule Octopus.Installation.Nation do
  @behaviour Octopus.Installation

  @panel_height 8
  @panel_width 8
  @panels 10
  @horizontal_spacing 20
  @pixels (for i <- 0..(@panels - 1), y <- 0..(@panel_height - 1), x <- 0..(@panel_width - 1) do
             {
               i * (@horizontal_spacing + @panel_width) + x,
               y
             }
           end)

  # @impl true
  def screens() do
    @panels
  end

  @impl true
  def pixels() do
    @pixels
  end

  @impl true
  def simulator_layouts() do
    [
      %Octopus.Layout{
        name: "Nation",
        positions: @pixels,
        width: @panel_width * @panels,
        height: @panel_height,
        pixel_size: {4, 4},
        pixel_margin: {0, 0, 0, 0},
        background_image: "/images/nation.webp",
        pixel_image: "/images/mildenberg-pixel-overlay.webp",
        image_size: {6458, Atom}
      }
    ]
  end
end
