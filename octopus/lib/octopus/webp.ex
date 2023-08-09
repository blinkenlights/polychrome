defmodule Octopus.WebP do
  alias Octopus.Canvas

  use Rustler,
    otp_app: :octopus,
    crate: :octopus_webp

  defstruct frames: [], size: nil

  def load(name) do
    Cachex.fetch!(__MODULE__, {name}, fn _ ->
      path = Path.join([:code.priv_dir(:octopus), "webp", "#{name}.webp"])

      if File.exists?(path) do
        {pixels, width, height} = decode_rgb(path)

        canvas = Canvas.new(width, height)

        canvas =
          pixels
          |> Enum.with_index()
          |> Enum.reduce(canvas, fn {[r, g, b], i}, acc ->
            x = rem(i, width)
            y = div(i, width)
            Canvas.put_pixel(acc, {x, y}, {r, g, b})
          end)

        {:commit, canvas}
      else
        raise "WebP #{path} not found"
      end
    end)
  end

  def decode_animation(_path), do: :erlang.nif_error(:nif_not_loaded)

  def encode_rgb(_rgb_pixels, _width, _height), do: :erlang.nif_error(:nif_not_loaded)

  def decode_rgb(_path), do: :erlang.nif_error(:nif_not_loaded)
end
