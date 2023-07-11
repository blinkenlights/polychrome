defmodule Octopus.Apps.SampleApp do
  use Octopus.App
  require Logger

  alias Octopus.{ColorPalette, Canvas}
  alias Octopus.Protobuf.InputEvent

  defmodule State do
    defstruct [:index, :color, :canvas]
  end

  @fps 60

  def name(), do: "Sample App"

  def init(_args) do
    state = %State{
      index: 0,
      color: 1,
      canvas: Canvas.new(80, 8, ColorPalette.load("pico-8"))
    }

    :timer.send_interval(trunc(1000 / @fps), :tick)

    {:ok, state}
  end

  def handle_info(:tick, %State{} = state) do
    coordinates = {rem(state.index, 80), trunc(state.index / 80)}

    canvas = Canvas.put_pixel(state.canvas, coordinates, state.color)

    canvas
    |> Canvas.to_frame()
    |> send_frame()

    {:noreply, %State{state | canvas: canvas, index: rem(state.index + 1, 640)}}
  end

  def handle_input(%InputEvent{type: :BUTTON_1, value: 1}, state) do
    {:noreply, %State{state | color: state.color + 1}}
  end

  def handle_input(%InputEvent{type: :BUTTON_2, value: 1}, state) do
    {:noreply, %State{state | color: max(0, state.color - 1)}}
  end

  def handle_input(_input_event, state) do
    {:noreply, state}
  end

  def handle_control_event(_event, state) do
    {:noreply, state}
  end
end
