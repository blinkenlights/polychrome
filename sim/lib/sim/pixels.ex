defmodule Sim.Pixels do
  use GenServer

  require Logger

  alias Sim.Protobuf.Packet
  alias Sim.Protobuf.Frame
  alias Sim.Protobuf.Config

  defmodule State do
    defstruct pixels: [], config: %{}

    @type t :: %__MODULE__{
            pixels: [integer()],
            config: %{
              max_value: non_neg_integer()
            }
          }

    @spec new :: t()
    def new do
      %__MODULE__{
        pixels: [],
        config: %{max_value: 8}
      }
    end

    @spec update(t(), Sim.Protobuf.Frame.t()) :: any
    def update(%State{config: %{max_value: max_value}} = state, %Frame{} = frame) do
      %State{state | pixels: frame.data |> :binary.bin_to_list(), config: %{max_value: max_value}}
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

  def encoded_pixels do
    GenServer.call(__MODULE__, :encoded_pixels)
  end

  def handle_packet(%Packet{content: {:config, config}}) do
    GenServer.call(__MODULE__, {:handle_config, config})
  end

  def handle_packet(%Packet{content: {:frame, frame}}) do
    GenServer.call(__MODULE__, {:handle_frame, frame})
  end

  def handle_call({:handle_config, %Config{} = _config}, _from, state) do
    {:reply, :ok, state}
  end

  def handle_call({:handle_frame, %Frame{} = frame}, _from, state) do
    {:reply, :ok, state |> State.update(frame) |> broadcast()}
  end

  def handle_call(:encoded_pixels, _from, %State{} = state) do
    {:reply, state.pixels |> :binary.list_to_bin(), state}
  end

  defp broadcast(%State{pixels: pixels, config: %{max_value: max_value}} = state) do
    Phoenix.PubSub.broadcast(
      Sim.PubSub,
      "pixels",
      {:pixels, pixels |> :binary.list_to_bin(), max_value}
    )

    state
  end
end
