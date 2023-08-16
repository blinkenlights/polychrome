defmodule Octopus.Sprite do
  alias Octopus.Canvas

  @doc """
  Lists all available sprite sheets in the priv/fonts directory.
  """
  def list_sprite_sheets() do
    Path.join(:code.priv_dir(:octopus), "sprites")
    |> File.ls!()
    |> Enum.filter(&String.ends_with?(&1, ".png"))
    |> Enum.map(fn file_name -> String.replace(file_name, ".png", "") end)
  end

  defp path(sprite_sheet), do: Path.join([:code.priv_dir(:octopus), "sprites", "#{sprite_sheet}.png"])

  def load(sprite_sheet) do
    path = path(sprite_sheet)
    if File.exists?(path) do
      {:ok, %ExPng.Image{} = image} = ExPng.Image.from_file(path)

      0..(trunc(image.width / 8) * trunc(image.height / 8) - 1)
      |> Enum.map(fn index ->
        extract_sprite(image, index)
      end)
    end
  end

  defp extract_sprite(%ExPng.Image{} = image, index) do
    x_start = rem(index * 8, image.width)
    y_start = trunc(index * 8 / image.width) * 8
    pixel_indices = for x <- 0..7, y <- 0..7, do: {x, y}

    acc = Canvas.new(8, 8)

    Enum.reduce(pixel_indices, acc, fn {x, y}, canvas ->
      case ExPng.Image.at(image, {x_start + x, y_start + y}) do
        <<_, _, _, 0>> ->
          canvas

        <<r, g, b, _>> ->
          Canvas.put_pixel(canvas, {x, y}, {r, g, b})

        nil ->
          Canvas.put_pixel(canvas, {x, y}, {0, 0, 0})
      end
    end)
  end

  @doc """
  Loads the sprite at the index from the given sprite sheet.

  Returns a canvas with the sprite pixels.
  """
  def load(sprite_sheet, index) do
    Cachex.fetch!(__MODULE__, {sprite_sheet, index}, fn _ ->
      path = path(sprite_sheet)

      if File.exists?(path) do
        {:ok, %ExPng.Image{} = image} = ExPng.Image.from_file(path)

        canvas = extract_sprite(image, index)

        {:commit, canvas}
      else
        raise "Sprite sheet #{sprite_sheet} not found at #{path}"
      end
    end)
  end

  def clear_cache() do
    Cachex.clear!(__MODULE__)
  end
end
