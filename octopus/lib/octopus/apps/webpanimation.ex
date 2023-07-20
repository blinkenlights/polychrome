defmodule Octopus.Apps.Webpanimation do
  use Octopus.App
  require Logger

  alias Octopus.{ColorPalette, Canvas}
  alias Octopus.WebP

  defmodule State do
    defstruct [:frames, :width, :height]
  end

  def name(), do: "Webp Animation"

  def init(_args) do
    path = Path.join([:code.priv_dir(:octopus), "webp", "marioi-run.webp"])
    decoded_animation = WebP.decode(path)
    {width, height} = decoded_animation.size
    state = %State{frames: decoded_animation.frames, width: width, height: height}
    Process.send_after(self(), :tick, 0)
    {:ok, state}
  end

  def handle_info(
        :tick,
        %State{frames: [animation_info | more_frames], width: width, height: height} = state
      ) do
    {pixels, timestamp} = animation_info

    canvas = Canvas.new(width, height)
    image = Enum.chunk_every(pixels, width)

    {canvas, _} =
      Enum.reduce(image, {canvas, 0}, fn row, {canvas, y} ->
        {canvas, _, y} =
          Enum.reduce(row, {canvas, 0, y}, fn pixel, {canvas, x, y} ->
            canvas =
              Canvas.put_pixel(
                canvas,
                {x, y},
                pixel
              )

            {canvas, x + 1, y}
          end)

        {canvas, y + 1}
      end)

    canvas
    |> Canvas.to_frame()
    |> send_frame()

    Process.send_after(self(), :tick, timestamp)
    {:noreply, %{state | frames: more_frames}}
  end
end
