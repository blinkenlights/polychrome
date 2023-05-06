defmodule Font do
  defstruct [:name, :variants]

  defmodule Variant do
    defstruct [:pixels, :palette]

    def from_rgba(rgba) do
      pixels =
        rgba
        |> :binary.bin_to_list()
        |> Enum.chunk_every(4)
        |> Enum.map(fn
          [_, _, _, 0] -> [0, 0, 0]
          [r, g, b, _] -> [r, g, b]
        end)

      palette_rgb = Enum.uniq(pixels)

      pixels =
        pixels
        |> Enum.map(&Enum.find_index(palette_rgb, fn value -> value == &1 end))

      palette = Enum.map(palette_rgb, &to_rgbw/1)

      %__MODULE__{
        pixels: pixels,
        palette: palette
      }
    end

    defp to_rgbw([r, g, b]) do
      min_value = min(r, min(g, b))
      [r - min_value, g - min_value, b - min_value, min_value]
    end
  end

  def load_fonts do
    {:ok, file_names} = Path.join(:code.priv_dir(:font), "fonts") |> File.ls()

    file_names
    |> Enum.map(&load_font/1)
  end

  def get_char(font, char, variant \\ 0) when char >= 32 do
    char_index = char - 32
    pixel_index = 8 * char_index
    variant = font.variants |> Enum.at(variant)

    pixels =
      0..8
      |> Enum.map(&Enum.slice(variant.pixels, &1 * 760 + pixel_index, 8))
      |> Enum.reverse()
      |> List.flatten()

    # pixels = Enum.slice(variant.pixels, pixel_index, 8 * 8)
    {pixels, variant.palette}
  end

  def load_font(file_name) do
    %{"name" => name} = Regex.named_captures(~r/\w+-(?<name>(.(?!\())+)/, file_name)
    path = Path.join(:code.priv_dir(:octopus), ["fonts/", file_name])
    {:ok, image} = ExPng.Image.from_file(path)

    variants_rgba =
      image.pixels
      # |> IO.inspect()
      |> Enum.chunk_every(8)
      |> Enum.map(&List.flatten/1)
      |> Enum.map(&Enum.join/1)

    variants = variants_rgba |> Enum.map(&Variant.from_rgba/1)

    %__MODULE__{
      name: name,
      variants: variants
    }
  end
end
