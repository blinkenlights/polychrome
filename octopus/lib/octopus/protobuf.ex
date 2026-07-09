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

  @doc """
  Prepends zero padding to pixel frame data so firmware with a higher
  `PANEL_INDEX` reads the correct slice from a single-panel frame.
  """
  def pad_for_panel_index(binary, panel_index, _pixel_count) when panel_index <= 1, do: binary

  def pad_for_panel_index(binary, panel_index, pixel_count)
      when is_binary(binary) and is_integer(panel_index) and panel_index > 0 and
             is_integer(pixel_count) and pixel_count > 0 do
    case Packet.decode(binary) do
      %Packet{content: {:rgb_frame, %RGBFrame{data: data} = frame}} ->
        pad_and_reencode(:rgb_frame, frame, data, panel_index, pixel_count, 3)

      %Packet{content: {:w_frame, %WFrame{data: data} = frame}} ->
        pad_and_reencode(:w_frame, frame, data, panel_index, pixel_count, 1)

      %Packet{content: {:rgb_frame_part1, %RGBFrame{data: data} = frame}}
      when panel_index <= 5 ->
        pad_and_reencode(:rgb_frame_part1, frame, data, panel_index, pixel_count, 3)

      %Packet{content: {:rgb_frame_part2, %RGBFrame{data: data} = frame}}
      when panel_index > 5 ->
        pad_and_reencode(:rgb_frame_part2, frame, data, panel_index - 5, pixel_count, 3)

      _ ->
        binary
    end
  end

  def pad_for_panel_index(binary, _panel_index, _pixel_count), do: binary

  defp pad_and_reencode(tag, frame, data, panel_index, pixel_count, bytes_per_pixel) do
    padding_size = (panel_index - 1) * pixel_count * bytes_per_pixel
    padding = :binary.copy(<<0>>, padding_size)

    %Packet{content: {tag, %{frame | data: padding <> data}}}
    |> Packet.encode()
  end

  def decode_firmware_packet(protobuf) when is_binary(protobuf) do
    case FirmwarePacket.decode(protobuf) do
      %FirmwarePacket{content: content} = packet when not is_nil(content) ->
        {:ok, packet}

      %FirmwarePacket{} ->
        {:error, :missing_content}
    end
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
