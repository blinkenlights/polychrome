defmodule Octopus.InputAdapter do
  use GenServer
  require Logger

  alias Octopus.{Protobuf, Mixer}
  alias Octopus.Protobuf.InputEvent

  @local_port 4423

  defmodule State do
    defstruct [:udp]
  end

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(:ok) do
    Logger.info("Starting input adapter. Listening on port #{@local_port}")
    {:ok, udp} = :gen_udp.open(@local_port, [:binary, active: true])

    {:ok, %State{udp: udp}}
  end

  def handle_info({:udp, _socket, _from_ip, _port, packet}, state = %State{}) do
    case Protobuf.decode_packet(packet) do
      {:ok, %InputEvent{} = input_event} ->
        # Logger.debug("#{__MODULE__}: Received input event: #{inspect(input_event)}")
        Mixer.handle_input(input_event)

      {:ok, content} ->
        Logger.warn("#{__MODULE__}: Received unexpected packet: #{inspect(content)}")

      {:error, error} ->
        Logger.warn("#{__MODULE__}: Error decoding packet #{inspect(error)}")
    end

    {:noreply, state}
  end
end
