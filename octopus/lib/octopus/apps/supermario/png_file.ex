# TODO Find a better name, currently a playground for initing the canvas with a png file
defmodule Octopus.Apps.Supermario.PngFile do
  alias Octopus.{ColorPalette, Canvas}

  @level_defs ~w(mario-1-1.reduced mario-1-2.reduced)
  @path "supermario"

  def init_canvas_for_level(level) when level > 0 and level < 2 do
    path = Path.join([:code.priv_dir(:octopus), @path, "#{Enum.at(@level_defs, level - 1)}.png"])

    {:ok, %ExPng.Image{pixels: pixels, height: height, width: width}} =
      ExPng.Image.from_file(path)

    canvas = Canvas.new(width, height)

    canvas =
      Enum.reduce(pixels, {canvas, 0}, fn row, {canvas, y} ->
        {canvas, _, y} =
          Enum.reduce(row, {canvas, 0, y}, fn pixel, {canvas, x, y} ->
            canvas = Canvas.put_pixel(canvas, {x, y}, pixel |> :binary.bin_to_list())
            {canvas, x + 1, y}
          end)

        {canvas, y + 1}
      end)

    canvas
  end

  def init_canvas_for_level(level), do: raise("level #{level} must be between 0 and 1")
end
