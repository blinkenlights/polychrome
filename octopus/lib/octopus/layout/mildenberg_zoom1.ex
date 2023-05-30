defmodule Octopus.Layout.MildenbergZoom1 do
  use Octopus.Layout

  @width 8
  @height 8
  @pixel_width 66
  @pixel_height 66
  @image_width 3041
  @image_height 3000
  @offset_x 1236
  @offset_y 1359
  @positions (for y <- 0..7, x <- 0..7 do
                {
                  @offset_x + x * @pixel_width,
                  @offset_y + y * @pixel_height
                }
              end)

  @impl true
  def layout do
    %Octopus.Layout{
      name: "Zoom 1",
      positions: @positions,
      width: @width,
      height: @height,
      pixel_size: {@pixel_width, @pixel_height},
      pixel_margin: {1, 1, 0, 0},
      image_size: {@image_width, @image_height},
      background_image: "/images/mildenberg-zoom1.webp",
      pixel_image: "/images/mildenberg-zoom1-pixel.webp"
    }
  end
end
