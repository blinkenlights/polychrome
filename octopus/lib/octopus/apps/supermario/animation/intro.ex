defmodule Octopus.Apps.Supermario.Animation.Intro do
  alias Octopus.Apps.Supermario.Animation

  def init_animation() do
    path = Path.join([:code.priv_dir(:octopus), "webp", "mario-run.webp"])
    decoded_animation = WebP.decode_animation(path)
    {width, height} = decoded_animation.size

    # state = %State{
    #   frames: convert_timestamps_to_duration(decoded_animation.frames),
    #   width: width,
    #   height: height
    # }
  end

  def draw(%Animation{} = animation) do
  end
end
