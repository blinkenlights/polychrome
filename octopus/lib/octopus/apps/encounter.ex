defmodule Octopus.Apps.Encounter do
  use Octopus.App
  require Logger

  alias Octopus.ColorPalette
  alias Octopus.Protobuf.{Frame, AudioFrame}

  defmodule State do
    defstruct [:palette, :index, :sequence]
  end

  def name(), do: "Encounter"

  def init(_args) do
    state = %State{
      palette: ColorPalette.load("pico-8"),
      index: 0,
      sequence: [
        {400, "file://encounter/high-1.wav", 1, 1},
        {400, "file://encounter/high-2.wav", 2, 2},
        {400, "file://encounter/high-3.wav", 3, 3},
        {400, "file://encounter/high-4.wav", 4, 4},
        {2000, "file://encounter/high-5.wav", 5, 8},
        {1000, "", 10, 0},
        {2000, "file://encounter/low-1.wav", 10, 11},
        {1000, "file://encounter/low-2.wav", 9, 12},
        {100, "file://encounter/low-1.wav", 10, 11},
        {25, "", 10, 0},
        {100, "file://encounter/low-1.wav", 10, 11},
        {25, "", 10, 0},
        {100, "file://encounter/low-1.wav", 10, 11},
        {25, "", 10, 0},
        {3000, "file://encounter/low-1.wav", 10, 11}
      ]
    }

    send(self(), :tick)

    {:ok, state}
  end

  def handle_info(:tick, %State{} = state) do
    {delay, uri, chan, col} = Enum.at(state.sequence, state.index)

    padding_left = List.duplicate(0, 64 * (chan - 1))
    padding_right = List.duplicate(0, 64 * (10 - chan))

    color = List.duplicate(col, 64)

    data = padding_left ++ color ++ padding_right

    send_frame(%Frame{data: data, palette: state.palette})

    send_frame(%AudioFrame{
      uri: uri,
      channel: chan
    })

    :timer.send_after(delay, self(), :tick)

    {:noreply, increment_index(state)}
  end

  defp increment_index(%State{index: index} = state) when index >= 14 do
    %State{state | index: 0}
  end

  defp increment_index(%State{index: index} = state) do
    %State{state | index: index + 1}
  end
end
