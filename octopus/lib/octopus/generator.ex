defmodule Octopus.Generator do
  use GenServer
  require Logger

  alias Octopus.{Broadcaster, ColorPalette}
  alias Octopus.Protobuf.{Config, Frame}

  @led_count 64
  @default_config %Config{
    color_palette: ColorPalette.from_file("flamingo-gb.hex"),
    easing_interval_ms: 1000,
    pixel_easing: :EASE_OUT_QUART,
    brightness_easing: :EASE_OUT_QUAD,
    show_test_frame: false
  }

  defstruct brightness: 0, config: @default_config, position: 0

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(:ok) do
    state = %__MODULE__{}

    update_config(state)

    # send(self(), :next_color)
    send(self(), :next_position)

    {:ok, state}
  end

  def handle_info(:next_color, %__MODULE__{} = state) do
    b = state.brightness + 1

    b =
      case b do
        c when c >= length(state.config.color_palette) -> 0
        c -> c
      end

    data =
      0..(@led_count - 1)
      |> Enum.map(fn _ -> b end)

    # |> List.update_at(19, fn _ -> b end)
    # update_config(state)

    %Frame{
      data: IO.iodata_to_binary(data)
    }
    |> Broadcaster.send()

    :timer.send_after(1000, :next_color)

    {:noreply, %__MODULE__{state | brightness: b}}
  end

  def handle_info(:next_position, %__MODULE__{} = state) do
    position =
      case state.position + 1 do
        c when c >= @led_count -> 5
        c -> c
      end

    data =
      Enum.map(0..(position - 1), fn _ -> 0 end) ++
        [1, 1, 2, 2, 3, 3] ++ Enum.map((position + 6)..(@led_count - 1), fn _ -> 0 end)

    %Frame{
      data: IO.iodata_to_binary(data)
    }
    |> Broadcaster.send()

    :timer.send_after(1000, :next_position)

    {:noreply, %__MODULE__{state | position: position}}
  end

  def update_config(%__MODULE__{} = state) do
    state.config
    |> Broadcaster.send()

    {:noreply, state}
  end
end
