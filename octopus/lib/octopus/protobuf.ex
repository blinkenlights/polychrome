defmodule Octopus.Protobuf do
  require Logger

  alias Octopus.ColorPalette
  alias Octopus.Protobuf.{Frame, Packet, Config, ClientPacket}

  def encode(%Frame{data: data, palette: palette} = frame)
      when is_binary(data) and is_binary(palette) do
    %Packet{content: {:frame, frame}}
    |> Packet.encode()
  end

  def encode(%Frame{data: list} = frame) when is_list(list) do
    %Frame{frame | data: IO.iodata_to_binary(list)}
    |> encode()
  end

  def encode(%Frame{palette: %ColorPalette{} = palette} = frame) do
    %Frame{frame | palette: ColorPalette.to_binary(palette)}
    |> encode()
  end

  def encode(%Config{} = config) do
    %Packet{content: {:config, config}}
    |> Packet.encode()
  end

  def decode_client_packet(protobuf) when is_binary(protobuf) do
    ClientPacket.decode(protobuf)
  rescue
    error ->
      Logger.error("Could not decode protobuf: #{inspect(error)} Binary: #{inspect(protobuf)} ")
      nil
  end
end
