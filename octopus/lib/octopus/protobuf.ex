defmodule Octopus.Protobuf do
  require Logger

  alias Octopus.Protobuf.{Frame, Packet, Config, ResponsePacket, Color}

  def encode(%Frame{} = frame) do
    %Packet{content: {:frame, frame}}
    |> Packet.encode()
  end

  def encode(%Config{} = config) do
    %Packet{content: {:config, config}}
    |> Packet.encode()
  end

  def decode_response(protobuf) when is_binary(protobuf) do
    ResponsePacket.decode(protobuf)
  rescue
    error ->
      Logger.error("Could not decode protobuf: #{inspect(error)} Binary: #{inspect(protobuf)} ")
      nil
  end
end
