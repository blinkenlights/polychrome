defmodule Octopus.WebP do
  use Rustler,
    otp_app: :octopus,
    crate: :octopus_webp

  defstruct frames: [], size: nil

  def decode_animation(_path), do: :erlang.nif_error(:nif_not_loaded)

  def encode(%Octopus.Canvas{} = canvas) do
    rgb_pixels =
      for y <- 0..(canvas.height - 1),
          x <- 0..(canvas.width - 1),
          do: Octopus.Canvas.get_pixel_color(canvas, {x, y})

    encode_rgb(List.flatten(rgb_pixels), canvas.width, canvas.height)
  end

  defp encode_rgb(_rgb_pixels, _width, _height), do: :erlang.nif_error(:nif_not_loaded)
end
