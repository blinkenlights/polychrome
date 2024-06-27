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
      case name do
        "BlinkenLightsRegular" ->
          {:commit, Octopus.Font.BlinkenLightsRegular.get()}

        _ ->
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
              |> Enum.zip(for(i <- 32..122, i not in 91..96, do: i))
              |> Map.new(fn {rgb, char} -> {char, rgb} end)
            end)

          {:commit, %__MODULE__{name: name, variants: variants}}
      end
    end)
  end

  @doc """
  Renders char but pipes better with canvas
  """
  def pipe_draw_char(canvas, font, char, variant, offset \\ {0, 0}),
    do: draw_char(font, char, variant, canvas, offset)

  @doc """
  Renders a single character onto a canvas and returns the canvas.
  """
  def draw_char(font, char, variant, canvas, {offset_x, offset_y} \\ {0, 0}) do
    char_pixels =
      font.variants
      |> Enum.at(variant, Enum.at(font.variants, 0))
      |> Map.get(char, List.duplicate({0, 0, 0}, 64))

    char_pixels
    |> Enum.with_index()
    |> Enum.reduce(canvas, fn {rgb, i}, canvas ->
      x = rem(i, 8)
      y = div(i, 8)
      Canvas.put_pixel(canvas, {x + offset_x, y + offset_y}, rgb)
    end)
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

  defmacro defbitmap(lines) do
    quote do
      max_width = Enum.max_by(unquote(lines), &String.length/1) |> String.length()
      top_padding = max(0, 8 - length(unquote(lines)))

      lines =
        (List.duplicate(String.duplicate(" ", max_width), top_padding) ++ unquote(lines))
        |> Enum.map(fn line ->
          if max_width > 8 do
            String.slice(line, 0, 8)
          else
            padding_left = div(8 - String.length(line), 2)
            padding_right = 8 - String.length(line) - padding_left
            String.duplicate(" ", padding_left) <> line <> String.duplicate(" ", padding_right)
          end
        end)

      for line <- lines,
          char <- to_charlist(line) do
        case char do
          ?X -> {255, 255, 255}
          _ -> {0, 0, 0}
        end
      end
    end
  end
end
