defmodule Mixer.Generator do
  use GenServer
  require Logger

  alias Mixer.{Broadcaster}
  alias Mixer.Protobuf.{Config, Frame}

  @maxval 255
  @led_count 64
  @default_config %Config{
    on_r: 50,
    on_g: 0,
    on_b: 0,
    on_w: 255,
    off_r: 0,
    off_g: 0,
    off_b: 0,
    off_w: 0,
    easing_interval_ms: 100,
    pixel_easing: :EASE_OUT_QUART,
    brightness_easing: :EASE_OUT_QUAD
  }

  defstruct brightness: 0, config: @default_config

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(:ok) do
    state = %__MODULE__{}

    update_config(state)

    send(self(), :next_brightness)

    {:ok, state}
  end

  def handle_info(:next_brightness, %__MODULE__{} = state) do
    b = state.brightness + 64

    b =
      case b do
        c when c == 256 -> 255
        c when c > 256 -> 0
        # c when c >= 3 -> 0
        c -> c
      end

    data =
      0..19
      |> Enum.map(fn _ -> 0 end)
      |> List.update_at(19, fn _ -> b end)

    %Frame{
      maxval: @maxval,
      data: IO.iodata_to_binary(data)
    }
    |> Broadcaster.send_frame()

    :timer.send_after(5000, :next_brightness)

    {:noreply, %__MODULE__{state | brightness: b}}
  end

  def update_config(%__MODULE__{} = state) do
    state.config
    |> Broadcaster.send_config()

    {:noreply, state}
  end
end
