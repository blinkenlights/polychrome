defmodule Octopus.Broadcaster do
  use GenServer
  require Logger

  alias Phoenix.Tracker.State
  alias Octopus.Protobuf
  alias Octopus.Protobuf.{FirmwareConfig, RemoteLog, FirmwareInfo, FirmwarePacket, ProximityEvent}
  alias Octopus.Installation

  @default_config %FirmwareConfig{
    luminance: 150,
    easing_mode: :EASE_OUT_QUART,
    show_test_frame: false,
    enable_calibration: true
  }

  defmodule State do
    defstruct [
      :udp,
      :config,
      :targets,
      :network_mode,
      :pixel_count,
      :remote_port,
      :should_send_udp,
      firmware_stats: %{}
    ]
  end

  defmodule FirmwareInfoMeta do
    defstruct [:last_seen, :firmware_info, :from_ip]
  end

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
    network_config = Installation.network_config()
    remote_port = Application.fetch_env!(:octopus, :firmware_broadcaster_remote_port)
    local_port = Application.fetch_env!(:octopus, :firmware_broadcaster_local_port)

    {targets, network_mode, should_send_udp} = determine_targets(network_config)
    pixel_count = Installation.panel_width() * Installation.panel_height()

    Logger.info(
      "Broadcasting to #{inspect(targets)}. Port #{remote_port}. Send UDP: #{should_send_udp}"
    )

    {:ok, udp} = :gen_udp.open(local_port, [:binary, active: true, broadcast: true])

    state = %State{
      udp: udp,
      config: @default_config,
      targets: targets,
      network_mode: network_mode,
      pixel_count: pixel_count,
      remote_port: remote_port,
      should_send_udp: should_send_udp
    }

    state = send_config(@default_config, state)

    Phoenix.PubSub.subscribe(Octopus.PubSub, Octopus.TelegramBot.topic())

    {:ok, state}
  end

  def handle_info({:bot_update, update}, %State{} = state) do
    case update["message"]["text"] do
      "bright" -> set_luminance(255)
      "normal" -> set_luminance(150)
      "dim" -> set_luminance(100)
      _ -> nil
    end

    {:noreply, state}
  end

  def handle_info({:udp, _socket, from_ip, _port, protobuf}, %State{} = state) do
    state =
      case Protobuf.decode_firmware_packet(protobuf) do
        {:ok, %FirmwarePacket{content: {_, content}}} ->
          handle_firmware_packet(content, from_ip, state)

        {:error, error} ->
          "#{print_ip(from_ip)}: Could not decode firmware packet: #{inspect(error)}"
          |> Logger.warning()

          state
      end

    {:noreply, state}
  end

  def handle_cast({:send_binary, frame}, %State{} = state) do
    frame
    |> send_binary(state)

    {:noreply, state}
  end

  def handle_cast({:set_luminance, luminance}, %State{} = state) do
    state =
      %FirmwareConfig{(%FirmwareConfig{} = state.config) | luminance: luminance}
      |> send_config(state)

    {:noreply, state}
  end

  def handle_cast({:set_calibration, set_calibration}, %State{} = state) do
    state =
      %FirmwareConfig{(%FirmwareConfig{} = state.config) | enable_calibration: set_calibration}
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
    if state.should_send_udp do
      for {target_ip, panel_index} <- state.targets do
        payload = frame_payload(binary, state, panel_index)

        Logger.debug(
          "Sending UDP Packet to #{inspect(target_ip)}:#{state.remote_port} (#{byte_size(payload)} bytes)"
        )

        :gen_udp.send(state.udp, target_ip, state.remote_port, payload)
      end
    else
      Logger.debug("UDP sending disabled - packets not sent")
    end
  end

  defp frame_payload(binary, %State{network_mode: :individual, pixel_count: pixel_count}, panel_index) do
    if Installation.num_panels() == 1 and panel_index > 1 do
      Protobuf.pad_for_panel_index(binary, panel_index, pixel_count)
    else
      binary
    end
  end

  defp frame_payload(binary, _state, _panel_index), do: binary

  defp handle_firmware_packet(%RemoteLog{message: message}, from_ip, %State{} = state) do
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

  defp handle_firmware_packet(%ProximityEvent{} = protobuf_event, _from_ip, %State{} = state) do
    Octopus.Events.Factory.create_proximity_event(protobuf_event)
    |> Octopus.Events.handle_event()

    state
  end

  defp update_firmware_stats(%FirmwareInfo{} = firmware_info, from_ip, %State{} = state) do
    stats = %FirmwareInfoMeta{
      last_seen: :os.system_time(:second),
      from_ip: from_ip,
      firmware_info: firmware_info
    }

    firmware_stats = Map.put(state.firmware_stats, firmware_info.mac, stats)

    %State{state | firmware_stats: firmware_stats}
  end

  defp determine_targets(network_config) do
    # Use Application.get_env to determine environment, defaulting to :prod
    current_env = Application.get_env(:octopus, :env, :prod)
    send_in_dev = Keyword.get(network_config, :send_in_dev, false)

    should_send_udp =
      case current_env do
        :dev -> send_in_dev
        _ -> true
      end

    network_mode = Keyword.get(network_config, :mode, :broadcast)

    targets =
      case network_mode do
        :broadcast ->
          broadcast_ip =
            case Keyword.get(network_config, :broadcast_ip, :auto) do
              :auto -> get_broadcast_ip()
              ip when is_binary(ip) -> resolve_address(ip)
              ip when is_tuple(ip) -> ip
            end

          [{broadcast_ip, 1}]

        :individual ->
          network_config
          |> Keyword.get(:panels, [])
          |> Enum.map(&resolve_panel_target/1)
      end

    {targets, network_mode, should_send_udp}
  end

  defp resolve_panel_target(panel) do
    address = Keyword.fetch!(panel, :address)
    panel_index = Keyword.get(panel, :panel_index, 1)
    {resolve_address(address), panel_index}
  end

  defp resolve_address(address) when is_binary(address), do: resolve_hostname(address)
  defp resolve_address(address) when is_tuple(address), do: address

  defp resolve_hostname(hostname) when is_binary(hostname) do
    case :inet.gethostbyname(String.to_charlist(hostname)) do
      {:ok, {:hostent, _, _, :inet, 4, [ip | _]}} ->
        ip

      {:error, _} ->
        Logger.warning("Could not resolve hostname: #{hostname}. Using localhost.")
        {127, 0, 0, 1}
    end
  end

  def get_broadcast_ip() do
    {:ok, ifaddrs} = :inet.getifaddrs()

    ifaddrs
    |> Enum.map(fn {_ifname, ifprops} -> Keyword.get(ifprops, :broadaddr) end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> case do
      [] ->
        {127, 0, 0, 1}

      [ip] ->
        ip

      [ip, _ | _] ->
        Logger.warning("Multiple broadcast IPs found. Using the first one: #{inspect(ip)}")
        ip
    end
  end
end
