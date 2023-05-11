defmodule Octopus.Apps.PaletteTester do
  use Octopus.App
  require Logger

  alias Octopus.ColorPalette
  alias Octopus.Protobuf.Frame

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
    # current_palette = Enum.at(@palettes, state.index) |> ColorPalette.from_file()
    current_palette = ColorPalette.from_file("pico-8")

    data = current_palette.colors |> Enum.with_index(fn _, i -> i end)
    fill = List.duplicate(0, 640 - Enum.count(data))

    %Frame{
      data: data ++ fill,
      palette: current_palette
    }
    |> send_frame()

    # Logger.info("Showing palette #{Enum.at(@palettes, state.index)}")

    :timer.send_after(100, self(), :tick)

    {:noreply, increment_index(state)}
  end

  defp increment_index(%State{index: index}) when index >= @max_index, do: %State{index: 0}
  defp increment_index(%State{index: index}), do: %State{index: index + 1}
end
