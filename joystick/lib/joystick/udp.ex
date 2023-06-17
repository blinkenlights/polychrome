defmodule Joystick.UDP do
  use GenServer
  require Logger

  alias Joystick.Protobuf
  alias Joystick.Protobuf.InputEvent

  @octopus_host "silence.local" |> String.to_charlist()
  @octopus_port 4423
  @local_port 4423

  defmodule State do
    defstruct [:udp]
  end

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def send(%InputEvent{} = input_event) do
    binary = Protobuf.encode(input_event)
    GenServer.cast(__MODULE__, {:send, binary})
  end

  def init(:ok) do
    {:ok, udp} = :gen_udp.open(@local_port, [:binary, active: false])

    {:ok, %State{udp: udp}}
  end

  def handle_cast({:send, binary}, %State{} = state) do
    case :gen_udp.send(state.udp, @octopus_host, @octopus_port, binary) do
      :ok ->
        # Logger.debug("Event send to #{@octopus_host}:#{@octopus_port}")
        :noop

      {:error, reason} ->
        Logger.warn("Failed to send to #{@octopus_host}:#{@octopus_port} : #{inspect(reason)}")
    end

    {:noreply, state}
  end
end
