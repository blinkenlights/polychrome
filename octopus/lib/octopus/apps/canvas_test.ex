defmodule Octopus.Apps.CanvasTest do
  alias Octopus.Canvas
  use Octopus.App, category: :test

  @tick_interval 50

  def name(), do: "Canvas Test"

  def init(_args) do
    :timer.send_interval(@tick_interval, self(), :tick)

    canvas =
      Canvas.new(80 + 9 * 18, 8)
      |> Canvas.polygon(
        [
          {2, 0},
          {5, 0},
          {7, 2},
          {7, 5},
          {5, 7},
          {2, 7},
          {0, 5},
          {0, 2}
        ],
        4
      )

    {:ok, %{canvas: canvas}}
  end

  def handle_info(:tick, %{canvas: canvas} = state) do
    canvas = canvas |> Canvas.translate({1, 0}, :wrap)
    canvas |> Canvas.to_frame(drop: true) |> send_frame()
    {:noreply, %{state | canvas: canvas}}
  end
end
