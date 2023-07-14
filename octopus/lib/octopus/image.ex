defmodule Octopus.Image do
  alias Octopus.Canvas

  @doc """
  Lists all available images in the priv/images directory.
  """
  def list_images() do
    Path.join(:code.priv_dir(:octopus), "images")
    |> File.ls!()
    |> Enum.filter(&String.ends_with?(&1, ".png"))
    |> Enum.map(fn file_name -> String.replace(file_name, ".png", "") end)
  end

  @doc """
  Loads image and returns an RGB canvas with the image pixels.
  """

  def load(image) do
    Cachex.fetch!(__MODULE__, {image}, fn _ ->
      path = Path.join([:code.priv_dir(:octopus), "images", "#{image}.png"])

      if File.exists?(path) do
        {:ok, %ExPng.Image{} = image} = ExPng.Image.from_file(path)

        canvas = Canvas.new(image.width, image.height)

        pixel_indices = for x <- 0..(image.width-1), y <- 0..(image.height-1), do: {x, y}

        canvas = Enum.reduce(pixel_indices, canvas, fn {x, y}, canvas ->
            color = ExPng.Image.at(image, {x, y})
            alpha = [color] |> Enum.map(fn <<_r, _g, _b, a>> -> a end) |> List.first()
            if alpha == 0 do
              canvas
            else
              rgb = [color] |> Enum.map(fn <<r, g, b, _a>> -> [r, g, b] end) |> List.flatten()
              Canvas.put_pixel(canvas, {x, y}, rgb)
            end
          end)

        {:commit, canvas}
      else
        raise "image #{image} not found"
      end
    end)
  end

  def clear_cache() do
    Cachex.clear!(__MODULE__)
  end
end
