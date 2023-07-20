defmodule Octopus.Apps.Webpanimation do
  use Octopus.App
  require Logger

  alias Octopus.{ColorPalette, Canvas}
  alias Octopus.WebP

  defmodule State do
    defstruct [:animation]
  end

  def name(), do: "Webp Animation"

  def init(_args) do
    path = Path.join([:code.priv_dir(:octopus), "webp", "marioi-run.webp"])
    animation = WebP.decode(path)
    state = %State{animation: animation}
    Process.send_after(self(), :tick, 0)
    {:ok, state}
  end

  def handle_info(:tick, %State{animation: animation} = state) do
    {pixels, timestamp} = List.first(animation.frames)
    # canvas = Canvas.put_pixel(state.canvas, coordinates, state.color)

    # canvas
    # |> Canvas.to_frame()
    # |> send_frame()

    {:noreply, state}
  end
end
