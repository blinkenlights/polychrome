defmodule Sim.Layout.Mildenberg do
  use Sim.Layout

  @width 8 * 10
  @height 8
  @pixel_width 11
  @pixel_height 11
  @image_width 3163
  @image_height 2500
  @offset_x 207
  @offset_y 1740
  @spacing 204
  @positions (for i <- 0..9, y <- 0..7, x <- 0..7 do
                {
                  @offset_x + i * (@spacing + @pixel_width * 8) + x * @pixel_width,
                  @offset_y + y * @pixel_height
                }
              end)

  @impl true
  def layout do
    %Sim.Layout{
      name: "Mildenberg",
      positions: @positions,
      width: @width,
      height: @height,
      pixel_size: {@pixel_width, @pixel_height},
      image_size: {@image_width, @image_height},
      background_image: "/images/mildenberg.jpg"
    }
  end
end
