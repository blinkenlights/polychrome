defmodule Octopus.Broadcaster do
  use GenServer
  require Logger

  alias Phoenix.Tracker.State
  alias Octopus.Protobuf
  alias Octopus.Protobuf.{FirmwareConfig, RemoteLog, FirmwareInfo, FirmwarePacket}

  @default_config %FirmwareConfig{
    luminance: 150,
    easing_mode: :EASE_OUT_QUART,
    show_test_frame: false,
    enable_calibration: true
  }

  defmodule State do
    defstruct [:udp, :config, :remote_ip, firmware_stats: %{}]
  end

  defmodule FirmwareInfoMeta do
    defstruct [:last_seen, :firmware_info, :from_ip]
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
    target_ip = {192, 168, 23, 255}
    # case Application.get_env(:octopus, :broadcast) do
    #   true -> get_broadcast_ip()
    #   false -> {127, 0, 0, 1}
    # end

    Logger.info("Broadcasting to #{inspect(target_ip)}. Port #{@remote_port}")

    {:ok, udp} = :gen_udp.open(@local_port, [:binary, active: true, broadcast: true])

    state = %State{
      udp: udp,
      config: @default_config,
      remote_ip: target_ip
    }

    state = send_config(@default_config, state)

    Phoenix.PubSub.subscribe(Octopus.PubSub, Octopus.TelegramBot.topic())

    {:ok, state}
  end

  def handle_info({:bot_update, update}, state) do
    case update["message"]["text"] do
      "bright" -> set_luminance(255)
      "normal" -> set_luminance(150)
      "dim" -> set_luminance(100)
      _ -> nil
    end

    {:noreply, state}
  end

  def handle_info({:udp, _socket, from_ip, _port, protobuf}, state = %State{}) do
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
    stats = %FirmwareInfoMeta{
      last_seen: :os.system_time(:second),
      from_ip: from_ip,
      firmware_info: firmware_info
    }

    firmware_stats = Map.put(state.firmware_stats, firmware_info.mac, stats)

    %State{state | firmware_stats: firmware_stats}
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
