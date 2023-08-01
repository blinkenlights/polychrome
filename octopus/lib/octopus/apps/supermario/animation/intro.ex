defmodule Octopus.Apps.Supermario.Animation.Intro do
  alias Octopus.Apps.Supermario.Animation
  alias Octopus.Canvas
  alias Octopus.WebP

  # we need to now all current game pixels and the position of mario
  # we rotage marios colour and draw a radial boom effect from marios position
  def new() do
    path = Path.join([:code.priv_dir(:octopus), "webp", "marioi-run.webp"])
    decoded_animation = WebP.decode_animation(path)
    {width, height} = decoded_animation.size

    data = %{
      frames: decoded_animation.frames,
      width: width,
      height: height
    }

    Animation.new(:intro, data)
  end

  def draw(%Animation{start_time: start_time, data: data}) do
    diff = Time.diff(Time.utc_now(), start_time, :millisecond)

    data.frames
    |> find_frame(diff)
    |> Enum.chunk_every(data.width)
  end

  defp find_frame([{pixels, timestamp} | tail], timediff) when timediff < timestamp, do: pixels
  defp find_frame([{pixels, _timestamp}], _timediff), do: pixels

  defp find_frame([_hd | tail], diff), do: find_frame(tail, diff)
end
