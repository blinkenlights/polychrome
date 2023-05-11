defmodule Octopus.UdpServer do
  use GenServer

  require Logger

  alias Octopus.Protobuf.Packet
  alias Octopus.Pixels

  def start_link(opts) do
    port = Keyword.fetch!(opts, :port)
    GenServer.start_link(__MODULE__, port, opts)
  end

  def init(port) do
    {:ok, socket} = :gen_udp.open(port, [:binary, active: true])
    Logger.info("Listening for UDP packets on port #{port}")
    {:ok, %{socket: socket}}
  end

  def subscribe do
    GenServer.cast(__MODULE__, {:subscribe, self()})
  end

  def handle_info({:udp, _socket, _ip, _port, data}, state) do
    packet =
      try do
        Packet.decode(data)
      rescue
        err ->
          Logger.error("Failed to decode: #{inspect(data)}, #{inspect(err)}")
          nil
      end

    if packet do
      Pixels.handle_packet(packet)
    end

    {:noreply, state}
  end
end
