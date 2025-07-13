defmodule Joystick.UDP do
  use GenServer
  require Logger

  alias Joystick.Protobuf
  alias Joystick.Protobuf.{InputEvent, InputLightEvent}
  alias Joystick.LightControl

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
    # Configuration is centralized in config.exs
    local_port = Application.fetch_env!(:joystick, :local_port)
    {:ok, udp} = :gen_udp.open(local_port, [:binary, active: true])

    {:ok, %State{udp: udp}}
  end

  def handle_cast({:send, binary}, %State{} = state) do
    octopus_host = Application.fetch_env!(:joystick, :octopus_host)
    octopus_port = Application.fetch_env!(:joystick, :octopus_port)

    case MdnsLite.gethostbyname(octopus_host) do
      {:ok, ip} ->
        case :gen_udp.send(state.udp, {ip, octopus_port}, binary) do
          :ok ->
            # Logger.debug("Event send to #{octopus_host}:#{octopus_port}")
            :noop

          {:error, reason} ->
            Logger.warning(
              "Failed to send to #{octopus_host}:#{octopus_port} : #{inspect(reason)}"
            )
        end

      {:error, _} ->
        Logger.warning("Failed to get IP for #{octopus_host}")
        :noop
    end

    {:noreply, state}
  end

  def handle_info({:udp, _socket, from_ip, _port, packet}, state = %State{}) do
    case Protobuf.decode(packet) do
      {:ok, %InputLightEvent{} = input_event} ->
        Logger.debug("Received light event from #{inspect(from_ip)}: #{inspect(input_event)}")
        LightControl.handle_light_event(input_event)

      _ ->
        :noop
    end

    {:noreply, state}
  end
end
