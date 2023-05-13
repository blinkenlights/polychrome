defmodule Octopus.Apps.PaletteTester do
  use Octopus.App
  require Logger

  alias Octopus.ColorPalette
  alias Octopus.Protobuf.{Frame, InputEvent}

  defmodule State do
    defstruct [:index]
  end

  @palettes ColorPalette.list_available()
  @max_index Enum.count(@palettes) - 1

  def name(), do: "Palette Tester"

  def init(_args) do
    state = %State{index: 0}

    send(self(), :tick)

    {:ok, state}
  end

  def handle_info(:tick, %State{} = state) do
    current_palette = Enum.at(@palettes, state.index) |> ColorPalette.load()

    data = current_palette.colors |> Enum.with_index(fn _, i -> i end)
    fill = List.duplicate(0, 640 - Enum.count(data))

    %Frame{
      data: data ++ fill,
      palette: current_palette
    }
    |> send_frame()

    :timer.send_after(100, self(), :tick)

    {:noreply, state}
  end

  # def handle_input(%InputEvent{type: :BUTTON, value: 0}, state) do
  #   {:noreply, increment_index(state)}
  # end

  def handle_input(%InputEvent{type: :BUTTON, value: 1}, state) do
    state = increment_index(state)

    Enum.at(@palettes, state.index) |> IO.inspect()
    {:noreply, state}
  end

  def handle_input(_input_event, state) do
    {:noreply, state}
  end

  defp increment_index(%State{index: index}) when index >= @max_index, do: %State{index: 0}
  defp increment_index(%State{index: index}), do: %State{index: index + 1}
end
