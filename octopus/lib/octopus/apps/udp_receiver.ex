defmodule Octopus.Apps.UdpReceiver do
  use Octopus.App
  require Logger

  alias Octopus.Protobuf
  alias Octopus.Protobuf.{Frame, InputEvent}

  @moduledoc """
  Will open a UDP port and listen for protobuf packets. All valid frames will be forwarded to the mixer.

  Any input events will be forwarded to the last IP address that sent a packet.
  """

  defmodule State do
    defstruct [:udp, :remote_ip, :remote_port]
  end

  @port 2342

  def name(), do: "UDP Server (Port: #{@port})"

  def init(_args) do
    Logger.info("#{__MODULE__}: Listening on UDP port #{inspect(@port)} for protobuf packets.")

    {:ok, udp} = :gen_udp.open(@port, [:binary, active: true])

    state = %State{
      udp: udp
    }

    {:ok, state}
  end

  def handle_info({:udp, _socket, ip, port, protobuf}, state = %State{}) do
    case Protobuf.decode_packet(protobuf) do
      {:ok, %Frame{} = frame} ->
        Logger.info("#{__MODULE__}: Received frame from #{inspect(ip)}:#{inspect(port)}")
        send_frame(frame)

      {:error, error} ->
        Logger.warn("#{__MODULE__}: Could not decode. #{inspect(error)} from #{inspect(ip)}")

        :noop
    end

    {:noreply, %State{state | remote_ip: ip, remote_port: port}}
  end

  def handle_input(%InputEvent{}, %State{remote_ip: nil} = state) do
    {:noreply, state}
  end

  def handle_input(%InputEvent{} = event, %State{} = state) do
    binary = Protobuf.encode(event)
    :gen_udp.send(state.udp, state.remote_ip, state.remote_port, binary)
    {:noreply, state}
  end
end
