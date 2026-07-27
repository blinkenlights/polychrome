defmodule Octopus.Osc.Server do
  use GenServer

  require Logger

  alias OSCx.Message
  alias OSCx.Bundle
  alias Octopus.Osc.Pixelfun3D
  alias Octopus.Osc.SoftTakeover
  alias Octopus.Osc.UiSync
  alias Octopus.Params.Global

  @client_timeout 60_000
  @client_timeout_check_interval 10_000
  @transport_topic "installation_transport"
  @global_topic "global_params"

  def start_link(_args) do
    GenServer.start_link(__MODULE__, [])
  end

  def init([]) do
    # Configuration is centralized in config.exs
    port = Application.fetch_env!(:octopus, :osc_server_port)
    Logger.info("Starting OSC server on port #{port}")
    {:ok, socket} = :gen_udp.open(port, [:binary])
    {:ok, _} = :timer.send_interval(@client_timeout_check_interval, :check_client_timeouts)

    Phoenix.PubSub.subscribe(Octopus.PubSub, @transport_topic)
    Phoenix.PubSub.subscribe(Octopus.PubSub, @global_topic)

    {:ok, %{socket: socket, clients: %{}, last_sync: nil}}
  end

  def handle_info(:check_client_timeouts, state) do
    now = DateTime.utc_now()

    state = %{
      state
      | clients:
          Map.reject(state.clients, fn {{ip, port}, last_seen} ->
            Logger.debug("Checking client timeout: #{inspect(last_seen)}")
            reject = DateTime.diff(now, last_seen, :millisecond) > @client_timeout
            if reject, do: Logger.debug("Client timed out: #{inspect(ip)}:#{inspect(port)}")
            reject
          end)
    }

    {:noreply, state}
  end

  def handle_info({:udp, _socket, ip, port, data}, state) do
    Logger.debug("Received packet: #{inspect(data)}")

    client = {ip, port}
    new_client? = not Map.has_key?(state.clients, client)
    state = %{state | clients: Map.put(state.clients, client, DateTime.utc_now())}

    # First packet from a client: push performance bank so TouchOSC can align.
    state =
      if new_client? do
        push_ui_sync(state, mark_client: client)
      else
        state
      end

    try do
      data
      |> OSCx.decode()
      |> handle_bundle_or_message(state, client)
    rescue
      error ->
        Logger.error("Error decoding OSC message: #{inspect(error)}")
    end

    {:noreply, state}
  end

  def handle_info({:installation_transport, public_state}, state) do
    snap = UiSync.snapshot_from_public(public_state)
    {:noreply, maybe_push_sync(snap, state)}
  end

  def handle_info({:param_updated, :speed, value}, state) do
    snap =
      case state.last_sync do
        %{tweaks: tweaks} -> %{global_speed: value, tweaks: tweaks}
        _ -> %{global_speed: value, tweaks: nil}
      end

    {:noreply, maybe_push_sync(snap, state)}
  end

  def handle_info({:param_updated, _key, _value}, state), do: {:noreply, state}

  def handle_bundle_or_message(%Message{} = message, state, client),
    do: handle_message(message, state, client)

  def handle_bundle_or_message(%Bundle{elements: messages_or_bundles}, state, client) do
    Enum.each(messages_or_bundles, &handle_bundle_or_message(&1, state, client))
  end

  defp handle_message(%Message{address: address, arguments: args}, state, client) do
    Logger.debug("Received #{inspect(address)} message with args: #{inspect(args)}")

    handle_message(String.split(address, "/", trim: true), args, state, client)
  end

  defp handle_message(["heartbeat"], _, _state, _client), do: nil

  defp handle_message(["global", "speed"], args, state, client) do
    case unwrap_number(args) do
      {:ok, value} ->
        actual = Global.speed()

        if SoftTakeover.accept?(client, :global_speed, value, actual) do
          Global.handle_param("speed", [value])
          put_param_and_reply("global", "speed", [value], state)
        else
          nil
        end

      :error ->
        Logger.warning("OSC /global/speed bad args: #{inspect(args)}")
    end
  end

  defp handle_message(["global", key], args, state, _client) do
    Global.handle_param(key, args)
    put_param_and_reply("global", key, args, state)
  end

  defp handle_message(["sim_3d", key], args, state, _client) do
    Octopus.Params.Sim3d.handle_param(key, args)
    put_param_and_reply("sim_3d", key, args, state)
  end

  defp handle_message(["sim_3d_aframe", key], args, state, _client) do
    Octopus.Params.Sim3d.handle_param(key, args)
    put_param_and_reply("sim_3d_aframe", key, args, state)
  end

  defp handle_message(["pixelfun3d" | rest], args, state, client) do
    case Pixelfun3D.handle(rest, args, client) do
      :handled ->
        # Actual values are pushed via InstallationTransport PubSub → UI-Sync.
        nil

      :held ->
        nil

      :sync ->
        push_ui_sync(state, mark_client: client)

      :legacy ->
        case rest do
          [key] -> put_param_and_reply("pixelfun3d", key, args, state)
          _ -> Logger.warning("Unknown legacy OSC /pixelfun3d/#{Enum.join(rest, "/")}")
        end

      :ignored ->
        nil

      :unknown ->
        Logger.warning(
          "Unknown OSC message: #{inspect(["pixelfun3d" | rest])} with args: #{inspect(args)}"
        )
    end
  end

  defp handle_message(["config"], [1.0], state, client) do
    messages =
      Octopus.Params.all()
      |> Enum.map(fn {{prefix, key}, value} ->
        %Message{address: "/#{prefix}/#{key}", arguments: [value]}
      end)

    bundle = OSCx.encode(%Bundle{elements: messages})

    state.clients
    |> Map.keys()
    |> Enum.each(fn {ip, port} -> :gen_udp.send(state.socket, ip, port, bundle) end)

    push_ui_sync(state, mark_client: client)
  end

  defp handle_message([prefix, key], args, state, _client) do
    put_param_and_reply(prefix, key, args, state)
  end

  defp handle_message(address, args, _state, _client) do
    Logger.warning("Unknown OSC message: #{inspect(address)} with args: #{inspect(args)}")
  end

  defp put_param_and_reply(prefix, key, args, state) do
    arg =
      case args do
        [arg] -> arg
        _ -> args
      end

    echo_osc([prefix, key], args, state)
    Octopus.Params.put(prefix, key, arg)
  end

  defp echo_osc(parts, args, state) do
    message = OSCx.encode(%Message{address: "/" <> Enum.join(parts, "/"), arguments: args})

    state.clients
    |> Map.keys()
    |> Enum.each(fn {ip, port} -> :gen_udp.send(state.socket, ip, port, message) end)
  end

  defp maybe_push_sync(snap, state) do
    if snap == state.last_sync do
      state
    else
      push_ui_sync(%{state | last_sync: snap}, mark_clients: Map.keys(state.clients), snap: snap)
    end
  end

  defp push_ui_sync(state, opts) do
    snap = Keyword.get(opts, :snap) || UiSync.snapshot()
    clients = Map.keys(state.clients)

    mark_targets =
      cond do
        (client = Keyword.get(opts, :mark_client)) != nil ->
          [client]

        (clients = Keyword.get(opts, :mark_clients)) != nil ->
          clients

        true ->
          Map.keys(state.clients)
      end

    messages = UiSync.messages(snap)

    unless messages == [] or clients == [] do
      bundle = OSCx.encode(%Bundle{elements: messages})

      Enum.each(clients, fn {ip, port} ->
        :gen_udp.send(state.socket, ip, port, bundle)
      end)
    end

    SoftTakeover.mark_clients_matched(mark_targets, UiSync.takeover_keys())

    %{state | last_sync: snap}
  end

  defp unwrap_number([value]) when is_number(value), do: {:ok, value * 1.0}

  defp unwrap_number([value]) when is_binary(value) do
    case Float.parse(value) do
      {n, _} -> {:ok, n}
      :error -> :error
    end
  end

  defp unwrap_number(_), do: :error
end
