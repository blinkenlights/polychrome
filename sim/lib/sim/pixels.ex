defmodule Sim.Pixels do
  use GenServer

  require Logger

  alias Sim.Protobuf.Packet
  alias Sim.Protobuf.Frame
  alias Sim.Protobuf.Config

  defmodule State do
    defstruct pixels: [], config: %Config{}

    @type t :: %__MODULE__{
            pixels: [integer()],
            config: Config.t()
          }

    @spec new :: t()
    def new do
      %__MODULE__{
        pixels: [],
        config: %Config{}
      }
    end
  end

  def start_link(opts) do
    GenServer.start_link(__MODULE__, [], opts)
  end

  def init(_) do
    {:ok, State.new()}
  end

  def subscribe do
    Phoenix.PubSub.subscribe(Sim.PubSub, "pixels")
  end

  def pixels do
    GenServer.call(__MODULE__, :pixels)
  end

  def config do
    GenServer.call(__MODULE__, :config)
  end

  def handle_packet(%Packet{content: {:config, config}}) do
    GenServer.call(__MODULE__, {:handle_config, config})
  end

  def handle_packet(%Packet{content: {:frame, frame}}) do
    GenServer.call(__MODULE__, {:handle_frame, frame})
  end

  def handle_call({:handle_config, %Config{} = config}, _from, state) do
    broadcast(config)
    {:reply, :ok, %State{state | config: config}}
  end

  def handle_call({:handle_frame, %Frame{} = frame}, _from, state) do
    pixels = frame.data |> :binary.bin_to_list()
    broadcast(pixels)
    {:reply, :ok, %State{state | pixels: pixels}}
  end

  def handle_call(:config, _from, %State{} = state) do
    {:reply, state.config, state}
  end

  def handle_call(:pixels, _from, %State{} = state) do
    {:reply, state.pixels, state}
  end

  defp broadcast(%Config{} = config) do
    Phoenix.PubSub.broadcast(Sim.PubSub, "config", {:config, config})
  end

  defp broadcast(pixels) when is_list(pixels) do
    Phoenix.PubSub.broadcast(Sim.PubSub, "pixels", {:pixels, pixels})
  end
end
