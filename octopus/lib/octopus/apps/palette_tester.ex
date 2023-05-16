defmodule Octopus.Apps.PaletteTester do
  use Octopus.App
  require Logger

  alias Octopus.ColorPalette
  alias Octopus.Protobuf.{Frame, InputEvent}

  defmodule State do
    defstruct [:index, :color]
  end

  @palettes ColorPalette.list_available()
  @max_index Enum.count(@palettes) - 1

  def name(), do: "Palette Tester"

  def init(_args) do
    state = %State{index: 0, color: 0}

    :timer.send_interval(100, :tick)

    {:ok, state}
  end

  def handle_info(:tick, %State{} = state) do
    current_palette = Enum.at(@palettes, state.index) |> ColorPalette.load()

    data = current_palette.colors |> Enum.with_index(fn _, i -> i end)
    # fill = List.duplicate(0, 640 - Enum.count(data))
    # data =
    #   List.duplicate(16, 64)
    #   |> List.update_at(6, fn _ -> state.color end)

    %Frame{
      data: data ++ List.duplicate(state.color, 640 - Enum.count(data)),
      palette: current_palette
    }
    |> send_frame()

    {:noreply, state}
  end

  def handle_input(%InputEvent{type: :BUTTON, value: 1}, state) do
    state = next_palette(state)
    Enum.at(@palettes, state.index) |> IO.inspect()
    {:noreply, state}
  end

  def handle_input(%InputEvent{type: :BUTTON, value: 2}, state) do
    state = next_color(state)
    IO.inspect(state.color)
    {:noreply, state}
  end

  def handle_input(_input_event, state) do
    {:noreply, state}
  end

  defp next_palette(%State{index: i} = state) when i >= @max_index,
    do: %State{state | index: 0, color: 0}

  defp next_palette(%State{index: i} = state), do: %State{state | index: i + 1, color: 0}

  defp next_color(%State{color: color, index: index} = state) do
    %ColorPalette{colors: colors} = Enum.at(@palettes, index) |> ColorPalette.load()

    color = rem(color + 1, Enum.count(colors))
    %State{state | color: color}
  end
end
