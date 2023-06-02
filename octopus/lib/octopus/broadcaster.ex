defmodule Octopus.Broadcaster do
  use GenServer
  require Logger

  alias Phoenix.Tracker.State
  alias Octopus.Protobuf
  alias Octopus.Protobuf.{FirmwareConfig, RemoteLog, FirmwareInfo, FirmwarePacket}

  @default_config %FirmwareConfig{
    luminance: 255,
    easing_mode: :EASE_OUT_QUART,
    show_test_frame: false,
    enable_calibration: true
  }

  defmodule State do
    defstruct [:udp, :file, :config]
  end

  # @remote_host "blinkenleds-1.fritz.box" |> to_charlist()
  # @remote_host {192, 168, 0, 172}
  # @remote_host {192, 168, 1, 255}
  @remote_host {192, 168, 0, 255}
  # @remote_host {192, 168, 43, 158}
  @remote_port 1337

  @local_port 4422

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def send_binary(binary) when is_binary(binary) do
    GenServer.cast(__MODULE__, {:send_binary, binary})
  end

  def set_luminance(luminance) when luminance < 256 do
    GenServer.cast(__MODULE__, {:set_luminance, luminance})
  end

  def set_calibration(set_calibration) when is_boolean(set_calibration) do
    GenServer.cast(__MODULE__, {:set_calibration, set_calibration})
  end

  def init(:ok) do
    Logger.info(
      "Broadcasting UPD to #{inspect(@remote_host)} port #{@remote_port}. Listening on #{@local_port}"
    )

    file = File.open!("remote.log", [:write])
    {:ok, udp} = :gen_udp.open(@local_port, [:binary, active: true, broadcast: true])

    state = %State{
      udp: udp,
      file: file,
      config: @default_config
    }

    send_config(@default_config, state)

    {:ok, state}
  end

  def handle_info({:udp, _socket, ip, _port, protobuf}, state = %State{}) do
    # todo: refactor

    case Protobuf.decode_firmware_packet(protobuf) do
      %FirmwarePacket{content: {:remote_log, %RemoteLog{message: message}}} ->
        IO.write(state.file, message)
        Logger.info("#{print_ip(ip)}: Remote log #{inspect(message)}")

      %FirmwarePacket{content: {:firmware_info, %FirmwareInfo{} = firmware_info}} ->
        # Logger.debug("#{print_ip(ip)}: Client info #{inspect(firmware_info)}")

        %FirmwareConfig{config_phash: expected_phash} = state.config

        case firmware_info do
          %FirmwareInfo{config_phash: ^expected_phash} ->
            :noop

          _ ->
            Logger.info(
              "#{print_ip(ip)}: Config hash misstmatch expected #{expected_phash} got #{firmware_info.config_phash}"
            )

            send_config(state.config, state)
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

  def handle_cast({:set_luminance, luminance}, %State{} = state) do
    state =
      %FirmwareConfig{state.config | luminance: luminance}
      |> send_config(state)

    {:noreply, state}
  end

  def handle_cast({:set_calibration, set_calibration}, %State{} = state) do
    state =
      %FirmwareConfig{state.config | enable_calibration: set_calibration}
      |> send_config(state)

    {:noreply, state}
  end

  defp print_ip({a, b, c, d}), do: "#{a}.#{b}.#{c}.#{d}"

  defp send_config(%FirmwareConfig{} = config, %State{} = state) do
    phash =
      config
      |> Map.from_struct()
      |> Map.drop([:config_phash])
      |> :erlang.phash2()

    config = %FirmwareConfig{config | config_phash: phash}

    config
    |> Protobuf.encode()
    |> send_binary(state)

    %State{state | config: config}
  end

  defp send_binary(binary, %State{} = state) do
    # Logger.debug("Sending UDP Packet: #{inspect(binary)}")
    :gen_udp.send(state.udp, @remote_host, @remote_port, binary)
  end
end
