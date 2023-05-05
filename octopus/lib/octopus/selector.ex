defmodule Octopus.Selector do
  use GenServer
  require Logger

  alias Octopus.Protobuf.{Config, Frame}

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

  defstruct config: @default_config

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(:ok) do
    state = %__MODULE__{}

    {:ok, state}
  end

  # TODO
end
