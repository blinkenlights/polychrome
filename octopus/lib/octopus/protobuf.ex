defmodule Octopus.Protobuf do
  require Logger

  alias Octopus.Protobuf.{
    Packet,
    WFrame,
    RGBFrame,
    AudioFrame,
    FirmwareConfig,
    FirmwarePacket,
    InputEvent,
    InputLightEvent,
    ControlEvent,
    SynthFrame,
    SoundToLightControlEvent
  }

  def encode(%WFrame{data: data} = wframe) when is_binary(data) do
    %Packet{content: {:w_frame, wframe}}
    |> Packet.encode()
  end

  def encode(%RGBFrame{data: data} = rgb_frame) when is_binary(data) do
    %Packet{content: {:rgb_frame, rgb_frame}}
    |> Packet.encode()
  end

  def encode(%AudioFrame{} = audio_frame) do
    %Packet{content: {:audio_frame, audio_frame}}
    |> Packet.encode()
  end

  def encode(%SynthFrame{} = synth_frame) do
    %Packet{content: {:synth_frame, synth_frame}}
    |> Packet.encode()
  end

  def encode(%InputEvent{} = event) do
    %Packet{content: {:input_event, event}}
    |> Packet.encode()
  end

  def encode(%InputLightEvent{} = event) do
    %Packet{content: {:input_light_event, event}}
    |> Packet.encode()
  end

  def encode(%FirmwareConfig{} = config) do
    %Packet{content: {:firmware_config, config}}
    |> Packet.encode()
  end

  def encode(%ControlEvent{} = event) do
    %Packet{content: {:control_event, event}}
    |> Packet.encode()
  end

  def split_and_encode(%RGBFrame{data: <<part1::binary-size(960), part2::binary>>} = rgbframe) do
    packet1 =
      %Packet{content: {:rgb_frame_part1, %RGBFrame{rgbframe | data: part1}}}
      |> Packet.encode()

    packet2 =
      %Packet{content: {:rgb_frame_part2, %RGBFrame{rgbframe | data: part2}}}
      |> Packet.encode()

    [packet1, packet2]
  end

  def split_and_encode(%RGBFrame{data: <<part1::binary>>} = rgbframe) do
    packet1 =
      %Packet{content: {:rgb_frame_part1, %RGBFrame{rgbframe | data: part1}}}
      |> Packet.encode()

    [packet1]
  end

  def split_and_encode(nil), do: []

  def decode_firmware_packet(protobuf) when is_binary(protobuf) do
    {:ok, FirmwarePacket.decode(protobuf)}
  rescue
    error ->
      {:error, error}
  end

  def decode_packet(protobuf) when is_binary(protobuf) do
    case Packet.decode(protobuf) do
      %Packet{content: {:wframe, %WFrame{} = frame}} ->
        {:ok, frame}

      %Packet{content: {:rgb_frame, %RGBFrame{} = frame}} ->
        {:ok, frame}

      %Packet{content: {:input_event, %InputEvent{} = input_event}} ->
        {:ok, input_event}

      %Packet{content: {:config, %FirmwareConfig{} = config}} ->
        {:ok, config}

      %Packet{content: {:sound_to_light_control_event, %SoundToLightControlEvent{} = stl_event}} ->
        {:ok, stl_event}

      _ ->
        {:error, :unexpected_content}
    end
  rescue
    error ->
      Logger.warning("Could not decode protobuf: #{inspect(error)} Binary: #{inspect(protobuf)} ")
      {:error, :decode_error}
  end
end
