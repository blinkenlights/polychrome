# TODO Find a better name, currently a playground for initing the canvas with a png file
defmodule Octopus.Apps.Supermario.PngFile do
  @level_defs ~w(mario-1-1.reduced mario-1-2.reduced)
  @path "supermario"

  def init_level(level) when level > 0 and level < 2 do
    path = Path.join([:code.priv_dir(:octopus), @path, "#{Enum.at(@level_defs, level - 1)}.png"])
    {:ok, %ExPng.Image{pixels: pixels}} = ExPng.Image.from_file(path)
    pixels
  end

  def init_levels(level), do: raise("level #{level} must be between 0 and 1")
end
