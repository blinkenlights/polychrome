defmodule Octopus.Apps.SampleApp do
  use Octopus.App
  require Logger

  alias Octopus.Protobuf.Frame

  defmodule State do
    defstruct [:index]
  end

  @palette Octopus.ColorPalette.from_file("lava-gb.hex")
  @pixel_count 640

  def name(), do: "Sample App"

  def init(_args) do
    state = %State{index: 0}

    :timer.send_interval(100, self(), :tick)

    {:ok, state}
  end

  def handle_info(:tick, %State{} = state) do
    data =
      0..(@pixel_count - 1)
      |> Enum.map(fn _ -> 0 end)
      |> List.update_at(state.index, fn _ -> 3 end)

    send_frame(%Frame{data: data, palette: @palette})

    {:noreply, increment_index(state)}
  end

  defp increment_index(%State{index: index}) when index >= @pixel_count, do: %State{index: 0}
  defp increment_index(%State{index: index}), do: %State{index: index + 1}
end
