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
    |> to_binary()
  end

  def from_binary(binary) do
    binary
    |> :binary.bin_to_list()
    |> Enum.chunk_every(4)
    |> Enum.map(fn [r, g, b, w] -> %Color{r: r, g: g, b: b, w: w} end)
  end

  def to_binary(palette) do
    palette
    |> Enum.map(fn %Color{r: r, g: g, b: b, w: w} -> [r, g, b, w] end)
    |> IO.iodata_to_binary()
  end

  def generate() do
    0..63
    # |> Enum.flat_map(fn i -> [%Color{r: i}, %Color{g: i}, %Color{b: i}, %Color{w: i}] end)
    |> Enum.map(fn i -> %Color{r: i * 4} end)
    |> brightness_correction()
    |> Enum.flat_map(fn %Color{r: r, g: g, b: b, w: w} -> [r, g, b, w] end)
    |> IO.iodata_to_binary()
  end

  def brightness_correction(palette) do
    palette
    |> Enum.map(fn color ->
      vals =
        color
        |> Map.from_struct()
        |> Enum.map(fn {c, v} -> {c, round(Easing.cubic_in(v / 255) * 255)} end)
        |> Enum.into(%{})

      struct(Color, vals)
    end)
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
