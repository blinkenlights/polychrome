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
    defstruct [:udp, :remote_log_file, :config, :remote_ip, firmware_stats: %{}]
  end

  defmodule FirmwareStats do
    defstruct [:hostname, :panel_index, :build_time, :last_seen, :ip, :fps, :config_phash]
  end

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

  def firmware_stats() do
    GenServer.call(__MODULE__, :firmware_stats)
  end

  def init(:ok) do
    {:ok, ifaddrs} = :inet.getifaddrs()

    broadast_ip =
      ifaddrs
      |> Enum.map(fn {_ifname, ifprops} -> Keyword.get(ifprops, :broadaddr) end)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> case do
        [] ->
          Logger.error("No broadcast IP found.")
          {127, 0, 0, 1}

        [ip] ->
          Logger.info("Using #{inspect(ip)} as broadcast address. Port #{@local_port}")
          ip

        [ip, _ | _] ->
          Logger.warn("Multiple broadcast IPs found. Using the first one: #{inspect(ip)}")
          ip
      end

    remote_log_file = File.open!("remote.log", [:write])
    {:ok, udp} = :gen_udp.open(@local_port, [:binary, active: true, broadcast: true])

    state = %State{
      udp: udp,
      remote_log_file: remote_log_file,
      config: @default_config,
      remote_ip: broadast_ip
    }

    state = send_config(@default_config, state)

    {:ok, state}
  end

  def handle_info({:udp, _socket, from_ip, _port, protobuf}, state = %State{}) do
    state =
      case Protobuf.decode_firmware_packet(protobuf) do
        {:ok, %FirmwarePacket{content: {_, content}}} ->
          handle_firmware_packet(content, from_ip, state)

        {:error, error} ->
          "#{print_ip(from_ip)}: Could not decode firmware packet: #{inspect(error)}"
          |> Logger.warn()

          state
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

  def handle_call(:firmware_stats, _from, %State{} = state) do
    {:reply, state.firmware_stats, state}
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
    :gen_udp.send(state.udp, state.remote_ip, @remote_port, binary)
  end

  defp handle_firmware_packet(%RemoteLog{message: message}, from_ip, %State{} = state) do
    IO.write(state.remote_log_file, message)
    Logger.info("#{print_ip(from_ip)}: Remote log #{inspect(message)}")
    state
  end

  defp handle_firmware_packet(%FirmwareInfo{} = firmware_info, from_ip, %State{} = state) do
    %FirmwareConfig{config_phash: expected_phash} = state.config

    state = update_firmware_stats(firmware_info, from_ip, state)

    case firmware_info do
      %FirmwareInfo{config_phash: ^expected_phash} ->
        state

      _ ->
        "#{firmware_info.hostname}: Config hash missmatch expected #{expected_phash} got #{firmware_info.config_phash}. Sending config."
        |> Logger.info()

        send_config(state.config, state)
    end
  end

  defp update_firmware_stats(%FirmwareInfo{} = firmware_info, from_ip, %State{} = state) do
    stats = %FirmwareStats{
      hostname: firmware_info.hostname,
      panel_index: firmware_info.panel_index,
      build_time: firmware_info.build_time |> String.to_integer(),
      last_seen: :os.system_time(:second),
      ip: from_ip,
      fps: firmware_info.fps,
      config_phash: firmware_info.config_phash
    }

    firmware_stats = Map.put(state.firmware_stats, from_ip, stats)

    %State{state | firmware_stats: firmware_stats}
  end
end
