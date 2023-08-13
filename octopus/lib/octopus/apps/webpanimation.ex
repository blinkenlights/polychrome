defmodule Octopus.Apps.Webpanimation do
  use Octopus.App, category: :animation
  require Logger

  alias Octopus.Canvas
  alias Octopus.WebP

  defmodule State do
    defstruct [:frames, :animation, :width, :height, :loop]
  end

  def name(), do: "Webp Animation"

  def config_schema() do
    %{
      animation: {"Animation", :string, %{default: "mario-run"}},
      loop: {"Loop", :boolean, %{default: true}}
    }
  end

  def init(%{animation: animation, loop: loop}) do
    state =
      %State{frames: [], animation: nil, width: 0, height: 0, loop: loop}
      |> load_animation(animation)

    send(self(), :tick)

    {:ok, state}
  end

  def get_config(%State{animation: animation, loop: loop}) do
    %{animation: animation, loop: loop}
  end

  defp load_animation(%State{} = state, animation) do
    path = Path.join([:code.priv_dir(:octopus), "webp", animation <> ".webp"])

    if File.exists?(path) do
      decoded_animation = WebP.decode_animation(path)
      {width, height} = decoded_animation.size
      frames = convert_timestamps_to_duration(decoded_animation.frames)

      %State{state | animation: animation, frames: frames, width: width, height: height}
    else
      state
    end
  end

  def handle_config(%{animation: animation, loop: loop}, %State{} = state) do
    state =
      if state.animation != animation do
        send(self(), :tick)
        load_animation(state, animation)
      else
        state
      end

    {:noreply, %State{state | loop: loop}}
  end

  def handle_info(:tick, %State{frames: [], loop: false}) do
    {:stop, :normal, nil}
  end

  def handle_info(:tick, %State{frames: [], loop: true} = state) do
    state = load_animation(state, state.animation)
    send(self(), :tick)
    {:noreply, state}
  end

  def handle_info(
        :tick,
        %State{frames: [animation_info | more_frames], width: width, height: height} = state
      ) do
    {pixels, duration} = animation_info

    canvas = Canvas.new(width, height)
    image = Enum.chunk_every(pixels, width)

    {canvas, _} =
      Enum.reduce(image, {canvas, 0}, fn row, {canvas, y} ->
        {canvas, _, y} =
          Enum.reduce(row, {canvas, 0, y}, fn [r, g, b], {canvas, x, y} ->
            canvas =
              Canvas.put_pixel(
                canvas,
                {x, y},
                {r, g, b}
              )

            {canvas, x + 1, y}
          end)

        {canvas, y + 1}
      end)

    canvas
    |> Canvas.to_frame(drop: width >= 242)
    |> send_frame()

    Process.send_after(self(), :tick, duration)
    {:noreply, %{state | frames: more_frames}}
  end

  defp convert_timestamps_to_duration(frames) do
    {new_frames, _} =
      Enum.reduce(frames, {[], 0}, fn {pixels, old_time_stamp}, {new_frames, last_time_stamp} ->
        {new_frames ++ [{pixels, old_time_stamp - last_time_stamp}], old_time_stamp}
      end)

    new_frames
  end
end
