defmodule Octopus.Layout.MildenbergZoom2 do
  use Octopus.Layout

  @width 8
  @height 8
  @pixel_width 221
  @pixel_height 221
  @image_width 2971
  @image_height 3533
  @offset_x 622
  @offset_y 796
  @positions (for y <- 0..7, x <- 0..7 do
                {
                  @offset_x + x * @pixel_width,
                  @offset_y + y * @pixel_height
                }
              end)

  @impl true
  def layout do
    %Octopus.Layout{
      name: "Zoom 2",
      positions: @positions,
      width: @width,
      height: @height,
      pixel_size: {@pixel_width, @pixel_height},
      pixel_margin: {4, 4, 0, 0},
      image_size: {@image_width, @image_height},
      background_image: "/images/mildenberg-zoom2.webp",
      pixel_image: "/images/mildenberg-zoom2-pixel-overlay.webp"
    }
  end
end
