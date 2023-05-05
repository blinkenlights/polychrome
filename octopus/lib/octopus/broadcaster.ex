# genserver that send udp packages to the led controller

defmodule Octopus.Broadcaster do
  use GenServer
  require Logger

  alias Octopus.Protobuf
  alias Octopus.Protobuf.{Frame, Config, RemoteLog, ClientInfo, ResponsePacket}

  defstruct [:udp, :file]

  # @remote_host "blinkenleds-1.fritz.box" |> to_charlist()
  # @remote_host {192, 168, 0, 255}
  @remote_host {192, 168, 23, 255}
  @remote_port 1337

  @local_port 4422

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def send_frame(%Frame{} = frame) do
    Protobuf.encode(frame)
    |> send_binary()
  end

  def send_config(%Config{} = config) do
    # todo: catch encoding errors
    Protobuf.encode(config)
    |> send_binary()
  end

  def send_binary(binary) when is_binary(binary) do
    GenServer.cast(__MODULE__, {:broadcast, binary})
  end

  def init(:ok) do
    Logger.info(
      "Broadcasting UPD to #{inspect(@remote_host)} port #{@remote_port}. Listening on #{@local_port}"
    )

    file = File.open!("remote.log", [:write])

    {:ok, udp} = :gen_udp.open(@local_port, [:binary, active: true, broadcast: true])

    {:ok, %__MODULE__{udp: udp, file: file}}
  end

  def handle_info({:udp, _socket, ip, _port, protobuf}, state = %__MODULE__{}) do
    case Protobuf.decode_response(protobuf) do
      %ResponsePacket{content: {:remote_log, %RemoteLog{message: message}}} ->
        IO.write(state.file, message)
        Logger.debug("Remote log #{print_ip(ip)}: #{inspect(message)}")

      %ResponsePacket{content: {:client_info, %ClientInfo{} = client_info}} ->
        Logger.info("Client info #{print_ip(ip)}: #{inspect(client_info)}")

      nil ->
        :noop
    end

    {:noreply, state}
  end

  def handle_cast({:broadcast, binary}, %__MODULE__{} = state) do
    # Logger.debug("Broadcaster: sending #{inspect(binary)}")
    :gen_udp.send(state.udp, @remote_host, @remote_port, binary)
    {:noreply, state}
  end

  def print_ip({a, b, c, d}), do: "#{a}.#{b}.#{c}.#{d}"
end
