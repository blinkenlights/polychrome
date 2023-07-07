defmodule Octopus.Apps.UdpReceiver do
  use Octopus.App
  require Logger

  alias Octopus.Protobuf
  alias Octopus.Protobuf.{Frame, RGBFrame, WFrame, InputEvent}

  @supported_frames [Frame, WFrame, RGBFrame]

  @moduledoc """
  Will open a UDP port and listen for protobuf packets. All valid frames will be forwarded to the mixer.

  Any input events will be forwarded to the last IP address that sent a packet.
  """

  defmodule State do
    defstruct [:udp, :remote_ip, :remote_port]
  end

  @port 2342

  def name(), do: "UDP Receiver (Port: #{@port})"

  def init(_args) do
    Logger.info("#{__MODULE__}: Listening on UDP port #{inspect(@port)} for protobuf packets.")

    {:ok, udp} = :gen_udp.open(@port, [:binary, active: true, ip: bind_address()])

    state = %State{
      udp: udp
    }

    {:ok, state}
  end

  def handle_info({:udp, _socket, ip, port, protobuf}, state = %State{}) do
    case Protobuf.decode_packet(protobuf) do
      {:ok, %frame_type{} = frame} when frame_type in @supported_frames ->
        Logger.debug("#{__MODULE__}: Received #{frame_type} from #{inspect(ip)}:#{inspect(port)}")
        send_frame(frame)

      {:error, error} ->
        Logger.warning("#{__MODULE__}: Could not decode. #{inspect(error)} from #{inspect(ip)}")

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

  def handle_control_event(event, state) do
    binary = Protobuf.encode(event)
    :gen_udp.send(state.udp, state.remote_ip, state.remote_port, binary)
    Logger.info("UDP: Control event received. #{inspect(event)}}")
    {:noreply, state}
  end

  # special case for fly.io
  defp bind_address() do
    case System.fetch_env("FLY_APP_NAME") do
      {:ok, _} ->
        {:ok, fly_global_ip} = :inet.getaddr(~c"fly-global-services", :inet)
        Logger.info("#{__MODULE__}: On fly.io, binding to #{inspect(fly_global_ip)}")
        fly_global_ip

      :error ->
        {0, 0, 0, 0}
    end
  end
end
