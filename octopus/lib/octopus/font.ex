defmodule Octopus.Font do
  alias Octopus.Canvas

  @doc """
  A selection of 8x8 fonts from https://nfggames.com/games/fontmaker/lister.php.

  Each font has multiple variants with different colors.
  """

  defstruct [:name, :variants]

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
      path = find_font_path(name)
      {:ok, img} = ExPng.Image.from_file(path)

      variants =
        img.pixels
        |> to_rgb()
        |> Enum.chunk_every(8)
        |> Enum.map(&List.flatten/1)
        |> Enum.map(fn variant ->
          variant
          |> Enum.chunk_every(8)
          |> Enum.chunk_every(div(img.width, 8))
          |> Enum.zip_with(&Function.identity/1)
          |> Enum.map(&List.flatten/1)
        end)

      {:commit, %__MODULE__{name: name, variants: variants}}
    end)
  end

  @doc """
  Renders a single character onto a canvas and returns the canvas.
  """
  def draw_char(font, char, variant, canvas, offset \\ {0, 0})

  def draw_char(%__MODULE__{} = font, char, variant, canvas, {offset_x, offset_y})
      when char >= 32 and char <= 126 do
    char_index = char - 32

    fallback_variant = Enum.at(font.variants, 0)

    variant_chars =
      font.variants
      |> Enum.at(variant, fallback_variant)

    fallback_char_pixels = Enum.at(variant_chars, 0)
    char_pixels = Enum.at(variant_chars, char_index, fallback_char_pixels)

    canvas =
      char_pixels
      |> Enum.with_index()
      |> Enum.reduce(canvas, fn {rgb, i}, canvas ->
        x = rem(i, 8)
        y = div(i, 8)
        Canvas.put_pixel(canvas, {x + offset_x, y + offset_y}, rgb)
      end)

    canvas
  end

  def draw_char(%__MODULE__{} = font, _char, variant, canvas, offset) do
    draw_char(font, 32, variant, canvas, offset)
  end

  defp to_rgb([]), do: []

  defp to_rgb([hd | tl]) when is_list(hd) do
    [to_rgb(hd) | to_rgb(tl)]
  end

  defp to_rgb([<<_, _, _, 0>> | tl]) do
    [{0, 0, 0} | to_rgb(tl)]
  end

  defp to_rgb([<<r, g, b, 255>> | tl]) do
    [{r, g, b} | to_rgb(tl)]
  end

  defp find_font_path(name) do
    font_dir = :code.priv_dir(:octopus) |> Path.join("fonts")

    File.ls!(font_dir)
    |> Enum.find(&String.starts_with?(&1, name))
    |> case do
      nil -> raise "Font #{name} not found"
      filename -> Path.join(font_dir, filename)
    end
  end
end
