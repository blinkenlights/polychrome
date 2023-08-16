# TODO Find a better name for this module
defmodule Octopus.Apps.Supermario.PngFile do
  @moduledoc """
  Reads a png file for a specific level and loads the pixels from it
  """

  @level_defs ~w(mario-1-1.reduced mario-1-2.reduced mario-1-3-reduced mario-1-4-reduced)
  @path "supermario"

  def load_image_for_level(level) when level > 0 and level < 4 do
    path = Path.join([:code.priv_dir(:octopus), @path, "#{Enum.at(@level_defs, level - 1)}.png"])

    # just make sure the height is 8 pixels
    {:ok, %ExPng.Image{pixels: pixels, height: 8}} = ExPng.Image.from_file(path)

    Enum.map(pixels, fn col ->
      Enum.map(col, fn <<r, g, b, _a>> -> [r, g, b] end)
    end)
  end

  def load_image_for_level(level), do: raise("level #{level} must be between 0 and 3")
end
