defmodule Octopus.Protobuf do
  require Logger

  alias Octopus.ColorPalette

  alias Octopus.Protobuf.{
    Packet,
    Frame,
    WFrame,
    AudioFrame,
    FirmwareConfig,
    FirmwarePacket,
    InputEvent
  }

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

  def encode(%WFrame{palette: palette, data: data} = wframe)
      when is_binary(palette) and is_binary(data) do
    %Packet{content: {:w_frame, wframe}}
    |> Packet.encode()
  end

  def encode(%AudioFrame{} = audio_frame) do
    %Packet{content: {:audio_frame, audio_frame}}
    |> Packet.encode()
  end

  def encode(%InputEvent{} = event) do
    %Packet{content: {:input_event, event}}
    |> Packet.encode()
  end

  def encode(%FirmwareConfig{} = config) do
    %Packet{content: {:firmware_config, config}}
    |> Packet.encode()
  end

  def decode_firmware_packet(protobuf) when is_binary(protobuf) do
    {:ok, FirmwarePacket.decode(protobuf)}
  rescue
    error ->
      {:error, error}
  end

  def decode_packet(protobuf) when is_binary(protobuf) do
    case Packet.decode(protobuf) do
      %Packet{content: {:frame, %Frame{palette: palette} = frame}} ->
        {:ok, %Frame{frame | palette: ColorPalette.from_binary(palette)}}

      %Packet{content: {:config, %FirmwareConfig{} = config}} ->
        {:ok, config}

      _ ->
        {:error, :unexpected_content}
    end
  rescue
    error ->
      Logger.warn("Could not decode protobuf: #{inspect(error)} Binary: #{inspect(protobuf)} ")
      {:error, :decode_error}
  end
end
