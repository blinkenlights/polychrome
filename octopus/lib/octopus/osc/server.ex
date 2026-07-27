defmodule Octopus.Osc.Server do
  use GenServer

  require Logger

  alias OSCx.Message
  alias OSCx.Bundle

  @client_timeout 60_000
  @client_timeout_check_interval 10_000

  def start_link(_args) do
    GenServer.start_link(__MODULE__, [])
  end

  def init([]) do
    # Configuration is centralized in config.exs
    port = Application.fetch_env!(:octopus, :osc_server_port)
    Logger.info("Starting OSC server on port #{port}")
    {:ok, socket} = :gen_udp.open(port, [:binary])
    {:ok, _} = :timer.send_interval(@client_timeout_check_interval, :check_client_timeouts)
    {:ok, %{socket: socket, clients: %{}}}
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

    state = %{state | clients: Map.put(state.clients, {ip, port}, DateTime.utc_now())}

    try do
      data
      |> OSCx.decode()
      |> handle_bundle_or_message(state)
    rescue
      error ->
        Logger.error("Error decoding OSC message: #{inspect(error)}")
    end

    {:noreply, state}
  end

  def handle_bundle_or_message(%Message{} = message, state), do: handle_message(message, state)

  def handle_bundle_or_message(%Bundle{elements: messages_or_bundles}, state) do
    Enum.each(messages_or_bundles, &handle_bundle_or_message(&1, state))
  end

  defp handle_message(%Message{address: address, arguments: args}, state) do
    Logger.debug("Received #{inspect(address)} message with args: #{inspect(args)}")

    handle_message(String.split(address, "/", trim: true), args, state)
  end

  defp handle_message(["heartbeat"], _, _state), do: nil

  defp handle_message(["global", key], args, state) do
    Octopus.Params.Global.handle_param(key, args)
    put_param_and_reply("global", key, args, state)
  end

  defp handle_message(["sim_3d", key], args, state) do
    Octopus.Params.Sim3d.handle_param(key, args)
    put_param_and_reply("sim_3d", key, args, state)
  end

  defp handle_message(["sim_3d_aframe", key], args, state) do
    Octopus.Params.Sim3d.handle_param(key, args)
    put_param_and_reply("sim_3d_aframe", key, args, state)
  end

  defp handle_message(["pixelfun3d" | rest], args, state) do
    case Octopus.Osc.Pixelfun3D.handle(rest, args) do
      :handled ->
        echo_osc(["pixelfun3d" | rest], args, state)

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

  defp handle_message(["config"], [1.0], state) do
    messages =
      Octopus.Params.all()
      |> Enum.map(fn {{prefix, key}, value} ->
        %Message{address: "/#{prefix}/#{key}", arguments: [value]}
      end)

    bundle = OSCx.encode(%Bundle{elements: messages})

    state.clients
    |> Map.keys()
    |> Enum.each(fn {ip, port} -> :gen_udp.send(state.socket, ip, port, bundle) end)
  end

  defp handle_message([prefix, key], args, state) do
    put_param_and_reply(prefix, key, args, state)
  end

  defp handle_message(address, args, _state) do
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
end
