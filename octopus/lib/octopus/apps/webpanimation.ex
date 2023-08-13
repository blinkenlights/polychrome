defmodule Octopus.Apps.Webpanimation do
  use Octopus.App, category: :animation
  require Logger

  alias Octopus.Canvas
  alias Octopus.WebP

  defmodule State do
    defstruct [:frames, :width, :height]
  end

  def name(), do: "Webp Animation"

  def init(_args) do
    path = Path.join([:code.priv_dir(:octopus), "webp", "mario-run.webp"])
    decoded_animation = WebP.decode_animation(path)
    {width, height} = decoded_animation.size

    state = %State{
      frames: convert_timestamps_to_duration(decoded_animation.frames),
      width: width,
      height: height
    }

    Process.send_after(self(), :tick, 0)
    {:ok, state}
  end

  def handle_info(
        :tick,
        %State{frames: []}
      ) do
    Logger.info("Animation finished")
    {:stop, :normal, nil}
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
