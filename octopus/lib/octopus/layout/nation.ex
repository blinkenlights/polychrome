defmodule Octopus.Layout.Nation do
  use Octopus.Layout

  @width 8 * 10
  @height 8
  @pixel_width 25
  @pixel_height 25
  @image_width 12900
  @image_height 5470
  @offset_x 1750
  @offset_y 3750
  @spacing 800
  @positions (for i <- 0..9, y <- 0..7, x <- 0..7 do
                {
                  @offset_x + i * (@spacing + @pixel_width * 8) + x * @pixel_width,
                  @offset_y + y * @pixel_height
                }
              end)

  @impl true
  def layout do
    %Octopus.Layout{
      name: "Default",
      positions: @positions,
      width: @width,
      height: @height,
      pixel_size: {@pixel_width, @pixel_height},
      pixel_margin: {0, 0, 0, 0},
      image_size: {@image_width, @image_height},
      background_image: "/images/nation.webp",
      pixel_image: "/images/mildenberg-pixel-overlay.webp"
    }
  end
end
