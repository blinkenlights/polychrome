defmodule Octopus.Sprite do
  alias Octopus.{ColorPalette, Canvas}

  @doc """
  Lists all available sprite sheets in the priv/fonts directory.
  """
  def list_sprite_sheets() do
    Path.join(:code.priv_dir(:octopus), "sprites")
    |> File.ls!()
    |> Enum.filter(&String.ends_with?(&1, ".png"))
    |> Enum.map(fn file_name -> String.replace(file_name, ".png", "") end)
  end

  @doc """
  Loads the sprite at the index from the given sprite sheet.

  Returns a canvas with the sprite pixels and a palette.
  """

  def load(sprite_sheet, index) do
    Cachex.fetch!(__MODULE__, {sprite_sheet, index}, fn _ ->
      path = Path.join([:code.priv_dir(:octopus), "sprites", "#{sprite_sheet}.png"])

      if File.exists?(path) do
        {:ok, %ExPng.Image{} = image} = ExPng.Image.from_file(path)

        unique_pixels = ExPng.Image.unique_pixels(image)

        palette =
          unique_pixels
          |> Enum.flat_map(fn <<r, g, b, _a>> -> [r, g, b] end)
          |> ColorPalette.from_binary()

        x_start = rem(index * 8, image.width)
        y_start = trunc(index * 8 / image.height) * 8
        pixel_indices = for x <- 0..7, y <- 0..7, do: {x, y}

        acc = Canvas.new(8, 8, palette)

        canvas =
          Enum.reduce(pixel_indices, acc, fn {x, y}, canvas ->
            case ExPng.Image.at(image, {x_start + x, y_start + y}) do
              <<_, _, _, 0>> ->
                canvas

              color ->
                color_index = Enum.find_index(unique_pixels, &match?(^color, &1))
                Canvas.put_pixel(canvas, {x, y}, color_index)
            end
          end)

        {:commit, canvas}
      else
        raise "Sprite sheet #{sprite_sheet} not found"
      end
    end)
  end

  def clear_cache() do
    Cachex.clear!(__MODULE__)
  end
end
