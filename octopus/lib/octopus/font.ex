defmodule Octopus.Font do
  alias Octopus.ColorPalette

  @doc """
  A selection of 8x8 fonts from https://nfggames.com/games/fontmaker/lister.php.

  Each font has multiple variants with different colors.
  """

  defstruct [:name, :variants]

  defmodule Variant do
    defstruct [:pixels, :palette]

    def from_rgba(rgba_pixels) do
      rbg_pixels =
        rgba_pixels
        |> :binary.bin_to_list()
        |> Enum.chunk_every(4)
        |> Enum.map(fn
          [_, _, _, 0] -> [0, 0, 0]
          [r, g, b, _] -> [r, g, b]
        end)

      palette = Enum.uniq(rbg_pixels)

      pixels = Enum.map(rbg_pixels, &Enum.find_index(palette, fn value -> value == &1 end))

      %__MODULE__{
        pixels: pixels,
        palette: palette |> List.flatten() |> ColorPalette.from_binary()
      }
    end
  end

  @doc """
  Lists all available fonts in the priv/fonts directory.
  """
  def list_available() do
    Path.join(:code.priv_dir(:octopus), "fonts")
    |> File.ls!()
    |> Enum.filter(&String.ends_with?(&1, ".png"))
    |> Enum.map(fn file_name -> String.replace(file_name, ".png", "") end)
  end

  @doc """
  Loads a font with all variants. Fonts are cached lazily, so the file system is only accessed on first read.
  """
  def load(name) do
    Cachex.fetch!(__MODULE__, name, fn _ ->
      path = Path.join([:code.priv_dir(:octopus), "fonts", "#{name}.png"])

      if File.exists?(path) do
        {:ok, %ExPng.Image{pixels: pixels}} = ExPng.Image.from_file(path)

        variants_rgba =
          pixels
          |> Enum.chunk_every(8)
          |> Enum.map(&List.flatten/1)
          |> Enum.map(&Enum.join/1)

        variants = variants_rgba |> Enum.map(&Variant.from_rgba/1)

        {:commit, %__MODULE__{name: name, variants: variants}}
      else
        raise "Font #{path} not found"
      end
    end)
  end

  @doc """
  Renders a single character.
  Returns the binary format for the protobuf [r, g, b, ...] and the color palette of the variant.
  """
  def render_char(%__MODULE__{} = font, char, variant) when char >= 32 do
    char_index = char - 32
    pixel_index = 8 * char_index
    variant = font.variants |> Enum.at(variant)

    pixels =
      0..8
      |> Enum.map(&Enum.slice(variant.pixels, &1 * 760 + pixel_index, 8))
      |> List.flatten()

    {pixels, variant.palette}
  end
end
