defmodule Octopus.Broadcaster do
  use GenServer
  require Logger

  alias Phoenix.Tracker.State
  alias Octopus.Protobuf
  alias Octopus.Protobuf.{FirmwareConfig, RemoteLog, FirmwareInfo, FirmwarePacket, ProximityEvent}
  alias Octopus.Hardware
  alias Octopus.Hardware.{InstallationValidator, PanelSlot, PanelStatusTracker}
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
      :default_remote_port,
      :should_send_udp,
      firmware_stats: %{},
      firmware_panel_index_map: %{}
    ]
  end

  defmodule FirmwareInfoMeta do
    defstruct [:last_seen, :firmware_info, :from_ip, :udp_port]
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

  @sending_topic "hardware:broadcaster:sending"

  @doc """
  Returns whether Octopus is sending UDP frames to firmware controllers.

  Reflects the runtime toggle. Initial state follows installation config: in
  `:dev`, sending starts enabled only when `send_in_dev: true`.
  """
  @spec sending_enabled?() :: boolean()
  def sending_enabled? do
    GenServer.call(__MODULE__, :sending_enabled?)
  end

  @doc """
  Enables or disables runtime UDP sending to firmware controllers.
  """
  @spec set_sending_enabled(boolean()) :: :ok
  def set_sending_enabled(enabled) when is_boolean(enabled) do
    GenServer.cast(__MODULE__, {:set_sending_enabled, enabled})
  end

  @doc "PubSub topic for runtime sending toggle changes."
  @spec sending_topic() :: String.t()
  def sending_topic, do: @sending_topic

  @doc "Subscribe to runtime sending toggle changes."
  @spec subscribe_sending_changes() :: :ok | {:error, term()}
  def subscribe_sending_changes do
    Phoenix.PubSub.subscribe(Octopus.PubSub, @sending_topic)
  end

  @doc false
  @spec config_allows_sending?(keyword()) :: boolean()
  def config_allows_sending?(network_config) when is_list(network_config) do
    current_env = Application.get_env(:octopus, :env, :prod)
    send_in_dev = Keyword.get(network_config, :send_in_dev, false)

    case current_env do
      :dev -> send_in_dev
      _ -> true
    end
  end

  def init(:ok) do
    validate_installation!()

    network_config = Installation.network_config()
    default_remote_port = Application.fetch_env!(:octopus, :firmware_broadcaster_remote_port)
    local_port = Application.fetch_env!(:octopus, :firmware_broadcaster_local_port)

    {targets, network_mode, should_send_udp} = determine_targets(network_config, default_remote_port)
    pixel_count = Installation.panel_width() * Installation.panel_height()

    {:ok, udp} = :gen_udp.open(local_port, [:binary, active: true, broadcast: true, reuseaddr: true])

    Logger.info(
      "Broadcasting to #{inspect(targets)}. Default remote port #{default_remote_port}. Send UDP: #{should_send_udp}"
    )

    state = %State{
      udp: udp,
      config: @default_config,
      targets: targets,
      network_mode: network_mode,
      pixel_count: pixel_count,
      default_remote_port: default_remote_port,
      should_send_udp: should_send_udp,
      firmware_panel_index_map: build_firmware_panel_index_map()
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

  def handle_info({:udp, _socket, {from_ip, from_port}, protobuf}, %State{} = state) do
    handle_udp_packet(from_ip, from_port, protobuf, state)
  end

  def handle_info({:udp, _socket, from_ip, from_port, protobuf}, %State{} = state) do
    handle_udp_packet(from_ip, from_port, protobuf, state)
  end

  def handle_info({:udp, _socket, from_ip, from_port, _anc_data, protobuf}, %State{} = state) do
    handle_udp_packet(from_ip, from_port, protobuf, state)
  end

  defp handle_udp_packet(from_ip, from_port, protobuf, %State{} = state) do
    state =
      case Protobuf.decode_firmware_packet(protobuf) do
        {:ok, %FirmwarePacket{content: {_, content}}} ->
          handle_firmware_packet(content, from_ip, from_port, state)

        {:error, :missing_content} ->
          Logger.debug(
            "#{print_ip(from_ip)}:#{from_port}: Ignoring undecodable firmware packet (#{byte_size(protobuf)} bytes)"
          )

          state

        {:error, error} ->
          Logger.debug(
            "#{print_ip(from_ip)}:#{from_port}: Could not decode firmware packet: #{inspect(error)}"
          )

          state
      end

    {:noreply, state}
  rescue
    e in UndefinedFunctionError ->
      Logger.debug("Ignoring firmware UDP packet during reload: #{Exception.message(e)}")
      {:noreply, state}
  end

  def handle_cast({:set_sending_enabled, enabled}, %State{} = state) do
    if state.should_send_udp == enabled do
      {:noreply, state}
    else
      Logger.info("Panel UDP sending #{if enabled, do: "enabled", else: "disabled"}")

      state = %{state | should_send_udp: enabled}
      state = if enabled, do: send_config(state.config, state), else: state

      broadcast_sending_changed(enabled)

      {:noreply, state}
    end
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

  def handle_call(:sending_enabled?, _from, %State{} = state) do
    {:reply, state.should_send_udp, state}
  end

  defp print_ip({a, b, c, d}), do: "#{a}.#{b}.#{c}.#{d}"
  defp print_ip(ip), do: inspect(ip)

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
      for {target_ip, panel_index, udp_port} <- state.targets do
        payload = frame_payload(binary, state, panel_index)
        :gen_udp.send(state.udp, target_ip, udp_port, payload)
      end
    end
  end

  defp frame_payload(binary, %State{network_mode: :individual, pixel_count: pixel_count}, panel_index) do
    if panel_index > 1 do
      Protobuf.pad_for_panel_index(binary, panel_index, pixel_count)
    else
      binary
    end
  end

  defp frame_payload(binary, _state, _panel_index), do: binary

  defp handle_firmware_packet(%RemoteLog{message: message}, from_ip, _from_port, %State{} = state) do
    Logger.info("#{print_ip(from_ip)}: Remote log #{inspect(message)}")
    state
  end

  defp handle_firmware_packet(%FirmwareInfo{} = firmware_info, from_ip, from_port, %State{} = state) do
    %FirmwareConfig{config_phash: expected_phash} = state.config

    state = update_firmware_stats(firmware_info, from_ip, from_port, state)
    PanelStatusTracker.firmware_info_received(firmware_info, from_ip)

    case firmware_info do
      %FirmwareInfo{config_phash: ^expected_phash} ->
        state

      _ ->
        "#{firmware_info.hostname}: Config hash missmatch expected #{expected_phash} got #{firmware_info.config_phash}. Sending config."
        |> Logger.info()

        send_config(state.config, state)
    end
  end

  defp handle_firmware_packet(%ProximityEvent{} = protobuf_event, _from_ip, _from_port, %State{} = state) do
    logical_panel =
      case Map.get(state.firmware_panel_index_map, protobuf_event.panel_index) do
        logical when is_integer(logical) ->
          logical

        nil when map_size(state.firmware_panel_index_map) == 0 ->
          protobuf_event.panel_index

        nil ->
          Logger.warning(
            "Ignoring proximity event from unknown firmware panel_index #{protobuf_event.panel_index}"
          )

          nil
      end

    if logical_panel do
      translated = %{protobuf_event | panel_index: logical_panel}

      Octopus.Events.Factory.create_proximity_event(translated)
      |> Octopus.Events.handle_event()
    end

    state
  end

  defp update_firmware_stats(%FirmwareInfo{} = firmware_info, from_ip, from_port, %State{} = state) do
    maybe_warn_catalog_mac_mismatch(firmware_info)

    stats = %FirmwareInfoMeta{
      last_seen: :os.system_time(:second),
      from_ip: from_ip,
      udp_port: from_port,
      firmware_info: firmware_info
    }

    key = {firmware_info.mac, from_port}
    firmware_stats = Map.put(state.firmware_stats, key, stats)

    %State{state | firmware_stats: firmware_stats}
  end

  defp determine_targets(network_config, default_remote_port) do
    should_send_udp = config_allows_sending?(network_config)
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

          udp_ports =
            Installation.panel_slots()
            |> Enum.map(&slot_udp_port/1)
            |> Enum.uniq()
            |> case do
              [] -> [default_remote_port]
              ports -> ports
            end

          Enum.map(udp_ports, fn udp_port -> {broadcast_ip, 1, udp_port} end)

        :individual ->
          case Installation.panel_slots() do
            [] ->
              network_config
              |> Keyword.get(:panels, [])
              |> Enum.map(&resolve_panel_target(&1, default_remote_port))

            panel_slots ->
              Enum.map(panel_slots, fn %PanelSlot{controller_id: controller_id, port: slot_port} ->
                controller = Hardware.fetch!(controller_id)

                {resolve_address(controller.hostname), controller.firmware_panel_index,
                 Octopus.Hardware.Controller.udp_port(controller, slot_port)}
              end)
          end
      end

    {targets, network_mode, should_send_udp}
  end

  defp slot_udp_port(%PanelSlot{controller_id: controller_id, port: slot_port}) do
    controller = Hardware.fetch!(controller_id)
    Octopus.Hardware.Controller.udp_port(controller, slot_port)
  end

  defp resolve_panel_target(panel, default_remote_port) do
    address = Keyword.fetch!(panel, :address)
    panel_index = Keyword.get(panel, :panel_index, 1)
    udp_port = Keyword.get(panel, :port, default_remote_port)
    {resolve_address(address), panel_index, udp_port}
  end

  defp resolve_address(address) when is_binary(address), do: resolve_hostname(address)
  defp resolve_address(address) when is_tuple(address), do: address

  defp resolve_hostname(hostname) when is_binary(hostname) do
    # .local needs mDNS. Erlang's resolver and container NSS often miss it;
    # mdns_lite already speaks multicast on the host network.
    case resolve_via_mdns(hostname) || resolve_via_inet(hostname) do
      {:ok, ip} ->
        ip

      :error ->
        Logger.warning("Could not resolve hostname: #{hostname}. Using localhost.")
        {127, 0, 0, 1}
    end
  end

  defp resolve_via_mdns(hostname) do
    if String.ends_with?(hostname, ".local") do
      case MdnsLite.gethostbyname(hostname) do
        {:ok, ip} -> {:ok, ip}
        {:error, _} -> nil
      end
    end
  end

  defp resolve_via_inet(hostname) do
    case :inet.gethostbyname(String.to_charlist(hostname)) do
      {:ok, {:hostent, _, _, :inet, 4, [ip | _]}} -> {:ok, ip}
      {:error, _} -> :error
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

  defp build_firmware_panel_index_map do
    Installation.panel_slots()
    |> Enum.with_index(1)
    |> Map.new(fn {%PanelSlot{controller_id: controller_id}, logical_panel} ->
      controller = Hardware.fetch!(controller_id)
      {controller.firmware_panel_index, logical_panel}
    end)
  end

  defp validate_installation! do
    installation_module = Application.fetch_env!(:octopus, :installation)

    opts = [
      panels: installation_module.panels(),
      panel_slots: installation_module.panel_slots(),
      panel_layout: installation_module.panel_layout(),
      network_config: installation_module.network_config()
    ]

    if opts[:panels] != [] do
      InstallationValidator.validate!(opts)
    end
  end

  defp maybe_warn_catalog_mac_mismatch(%FirmwareInfo{mac: mac, hostname: hostname}) do
    catalog_panel =
      Hardware.registry()
      |> Map.values()
      |> Enum.find(fn panel ->
        panel.mac == mac or panel.hostname == hostname
      end)

    case catalog_panel do
      %{mac: ^mac} ->
        :ok

      %{mac: catalog_mac, id: id} when not is_nil(catalog_mac) ->
        Logger.warning(
          "Firmware #{hostname} MAC #{mac} does not match catalog #{inspect(id)} expected #{catalog_mac}"
        )

      _ ->
        :ok
    end
  end

  defp broadcast_sending_changed(enabled) do
    Phoenix.PubSub.broadcast(Octopus.PubSub, @sending_topic, {:sending_changed, enabled})
    PanelStatusTracker.sending_changed(enabled)
  end
end
