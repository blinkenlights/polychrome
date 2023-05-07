defmodule Octopus.ColorPalette do
  @palette_dir "../color_palettes"

  defmodule Color do
    defstruct r: 0, g: 0, b: 0, w: 0
  end

  def from_file(filename) do
    Path.join(@palette_dir, filename)
    |> File.stream!()
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&match?("", &1))
    |> Enum.map(&color_from_hex/1)
    |> Enum.flat_map(fn %Color{r: r, g: g, b: b, w: w} -> [r, g, b, w] end)
    |> IO.iodata_to_binary()
  end

  def color_from_hex(<<r::binary-size(2), g::binary-size(2), b::binary-size(2)>>) do
    %Color{
      r: Integer.parse(r, 16) |> elem(0),
      g: Integer.parse(g, 16) |> elem(0),
      b: Integer.parse(b, 16) |> elem(0),
      w: 0
    }
  end
end