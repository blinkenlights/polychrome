defmodule Octopus.WebP do
  alias Octopus.Canvas

  use Rustler,
    otp_app: :octopus,
    crate: :octopus_webp

  defstruct frames: [], size: nil

  def load(name) do
    Cachex.fetch!(__MODULE__, {name, :still}, fn _ ->
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

  def load_animation(name) do
    Cachex.fetch!(__MODULE__, {name, :still}, fn _ ->
      path = Path.join([:code.priv_dir(:octopus), "webp", "#{name}.webp"])

      if File.exists?(path) do
        animation = decode_animation(path)
        {width, height} = animation.size

        frames =
          animation.frames
          |> convert_timestamps_to_duration()
          |> convert_frames_to_canvases(width, height)

        {:commit, frames}
      else
        raise "WebP #{path} not found"
      end
    end)
  end

  def decode_animation(_path), do: :erlang.nif_error(:nif_not_loaded)

  def encode_rgb(_rgb_pixels, _width, _height), do: :erlang.nif_error(:nif_not_loaded)

  def decode_rgb(_path), do: :erlang.nif_error(:nif_not_loaded)

  defp convert_timestamps_to_duration(frames) do
    {new_frames, _} =
      Enum.reduce(frames, {[], 0}, fn {pixels, old_time_stamp}, {new_frames, last_time_stamp} ->
        {new_frames ++ [{pixels, old_time_stamp - last_time_stamp}], old_time_stamp}
      end)

    new_frames
  end

  defp convert_frames_to_canvases(frames, width, height) do
    Enum.map(frames, fn {pixels, duration} ->
      canvas = Canvas.new(width, height)

      canvas =
        pixels
        |> Enum.with_index()
        |> Enum.reduce(canvas, fn {[r, g, b], i}, acc ->
          x = rem(i, width)
          y = div(i, width)
          Canvas.put_pixel(acc, {x, y}, {r, g, b})
        end)

      {canvas, duration}
    end)
  end
end
