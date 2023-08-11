defmodule Octopus.Apps.InputTester do
  use Octopus.App, category: :test
  require Logger

  alias Octopus.ColorPalette
  alias Octopus.Protobuf.{Frame, InputEvent}

  defmodule State do
    defstruct [:position, :color, :palette]
  end

  def name(), do: "Input Tester"

  def init(_args) do
    state = %State{position: 0, color: 1, palette: ColorPalette.load("pico-8")}

    send(self(), :tick)

    {:ok, state}
  end

  def handle_info(:tick, %State{} = state) do
    render_frame(state)

    {:noreply, state}
  end

  def handle_input(%InputEvent{type: :BUTTON_1, value: 1}, state) do
    state = %State{state | color: rem(state.color + 1, 16)}
    render_frame(state)
    {:noreply, state}
  end

  def handle_input(%InputEvent{type: :BUTTON_2, value: 1}, state) do
    state =
      case state.color do
        0 -> %State{state | color: 15}
        _ -> %State{state | color: state.color - 1}
      end

    render_frame(state)

    {:noreply, state}
  end

  def handle_input(%InputEvent{type: :AXIS_X_1, value: value}, state) do
    state = %State{state | position: max(0, state.position + value * -1)}
    render_frame(state)
    {:noreply, state}
  end

  def handle_input(_event, state) do
    # Logger.info("Unhandled input event: #{inspect(event)}")
    {:noreply, state}
  end

  defp render_frame(%State{} = state) do
    data =
      List.duplicate(0, 640)
      |> List.update_at(state.position, fn _ -> state.color end)

    %Frame{
      data: data,
      palette: state.palette
    }
    |> send_frame()
  end
end
