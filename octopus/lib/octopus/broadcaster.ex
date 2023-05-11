# genserver that send udp packages to the led controller

defmodule Octopus.Broadcaster do
  use GenServer
  require Logger

  alias Octopus.Protobuf
  alias Octopus.Protobuf.{Config, RemoteLog, ClientInfo, ClientPacket}

  @default_config %Config{
    luminance: 255,
    easing_interval_ms: 500,
    easing_mode: :EASE_OUT_QUART,
    show_test_frame: false
  }

  defstruct [:udp, :file, config: %Config{}]

  # @remote_host "blinkenleds-1.fritz.box" |> to_charlist()
  # @remote_host {192, 168, 0, 172}
  # @remote_host {192, 168, 1, 255}
  @remote_host {192, 168, 0, 255}
  # @remote_host {192, 168, 23, 255}
  @remote_port 1337

  @local_port 4422

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def send_binary(binary) when is_binary(binary) do
    GenServer.cast(__MODULE__, {:send_binary, binary})
  end

  def send_config(%Config{} = config) do
    GenServer.cast(__MODULE__, {:send_config, config})
  end

  def set_luminance(luminance) when luminance < 256 do
    GenServer.cast(__MODULE__, {:set_luminance, luminance})
  end

  def init(:ok) do
    Logger.info(
      "Broadcasting UPD to #{inspect(@remote_host)} port #{@remote_port}. Listening on #{@local_port}"
    )

    file = File.open!("remote.log", [:write])
    {:ok, udp} = :gen_udp.open(@local_port, [:binary, active: true, broadcast: true])

    send_config(@default_config)

    {:ok, %__MODULE__{udp: udp, file: file}}
  end

  def handle_info({:udp, _socket, ip, _port, protobuf}, state = %__MODULE__{}) do
    # todo: refactor

    case Protobuf.decode_client_packet(protobuf) do
      %ClientPacket{content: {:remote_log, %RemoteLog{message: message}}} ->
        IO.write(state.file, message)
        Logger.debug("#{print_ip(ip)}: Remote log #{inspect(message)}")

      %ClientPacket{content: {:client_info, %ClientInfo{} = client_info}} ->
        # Logger.debug("#{print_ip(ip)}: Client info #{inspect(client_info)}")

        %Config{config_phash: expected_phash} = state.config

        case client_info do
          %ClientInfo{config_phash: ^expected_phash} ->
            :noop

          _ ->
            Logger.info(
              "#{print_ip(ip)}: Config hash misstmacht expected #{expected_phash} got #{client_info.config_phash}"
            )

            send_config(state.config)
        end

      nil ->
        :noop
    end

    {:noreply, state}
  end

  def handle_cast({:send_binary, frame}, state) do
    frame
    |> send_binary(state)

    {:noreply, state}
  end

  def handle_cast({:send_config, config}, %__MODULE__{} = state) do
    phash =
      config
      |> Map.from_struct()
      |> Map.drop([:config_phash])
      |> :erlang.phash2()

    config = %Config{config | config_phash: phash}

    # TODO: this should probably be done somewhere else
    Phoenix.PubSub.broadcast(Octopus.PubSub, "mixer", {:mixer, {:config, config}})

    config
    |> Protobuf.encode()
    |> send_binary(state)

    {:noreply, %__MODULE__{state | config: config}}
  end

  def handle_cast({:set_luminance, luminance}, %__MODULE__{} = state) do
    %Config{state.config | luminance: luminance}
    |> send_config()

    {:noreply, state}
  end

  defp print_ip({a, b, c, d}), do: "#{a}.#{b}.#{c}.#{d}"

  defp send_binary(binary, %__MODULE__{} = state) do
    # Logger.debug("Sending UDP Packet: #{inspect(binary)}")
    :gen_udp.send(state.udp, @remote_host, @remote_port, binary)
  end
end
