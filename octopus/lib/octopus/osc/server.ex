defmodule Octopus.Osc.Server do
  use GenServer

  require Logger

  alias OSCx.Message
  alias OSCx.Bundle

  def start_link(port \\ 8000) do
    GenServer.start(__MODULE__, port)
  end

  def init(port) do
    Logger.info("Starting OSC server on port #{port}")
    :gen_udp.open(port, [:binary])
  end

  def handle_info({:udp, socket, ip, port, data}, socket) do
    Logger.debug("Received packet: #{inspect(data)}")

    data
    |> OSCx.decode()
    |> handle_bundle_or_message({socket, ip, port})

    {:noreply, socket}
  end

  def handle_bundle_or_message(%Message{} = message, addr), do: handle_message(message, addr)

  def handle_bundle_or_message(%Bundle{elements: messages_or_bundles}, addr) do
    Enum.each(messages_or_bundles, &handle_bundle_or_message(&1, addr))
  end

  defp handle_message(%Message{address: address, arguments: args}, addr) do
    Logger.debug("Received #{inspect(address)} message with args: #{inspect(args)}")

    handle_message(String.split(address, "/", trim: true), args, addr)
  end

  defp handle_message(["config"], [1.0], {socket, ip, port}) do
    messages =
      Octopus.Params.all()
      |> Enum.map(fn {{prefix, key}, value} ->
        %Message{address: "/#{prefix}/#{key}", arguments: [value]}
      end)

    :gen_udp.send(socket, ip, port, OSCx.encode(%Bundle{elements: messages}))
  end

  defp handle_message([prefix, key], [arg], _addr) do
    Octopus.Params.put(prefix, key, arg)
  end

  defp handle_message(address, args, _addr) do
    Logger.warning("Unknown OSC message: #{inspect(address)} with args: #{inspect(args)}")
  end
end
