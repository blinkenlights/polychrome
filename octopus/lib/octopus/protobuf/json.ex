alias Octopus.Protobuf.FirmwareConfig
alias Octopus.Protobuf.{Frame, RGBFrame, WFrame, AudioFrame}

defimpl Jason.Encoder, for: FirmwareConfig do
  def encode(%FirmwareConfig{} = config, opts) do
    config
    |> Map.from_struct()
    |> Jason.Encode.map(opts)
  end
end

defimpl Jason.Encoder, for: Frame do
  def encode(%Frame{data: data} = frame, opts) do
    %Frame{frame | data: to_char_list(data)}
    |> Map.from_struct()
    |> Map.put(:kind, "indexed")
    |> Jason.Encode.map(opts)
  end
end

defimpl Jason.Encoder, for: RGBFrame do
  def encode(%RGBFrame{data: data} = frame, opts) do
    %RGBFrame{frame | data: :binary.bin_to_list(data)}
    |> Map.from_struct()
    |> Map.put(:kind, "rgb")
    |> Jason.Encode.map(opts)
  end
end

defimpl Jason.Encoder, for: WFrame do
  def encode(%WFrame{data: data} = frame, opts) do
    %WFrame{frame | data: :binary.bin_to_list(data)}
    |> Map.from_struct()
    |> Map.put(:kind, "rgbw")
    |> Jason.Encode.map(opts)
  end
end

defimpl Jason.Encoder, for: AudioFrame do
  def encode(%AudioFrame{} = frame, opts) do
    frame
    |> Map.from_struct()
    |> Map.put(:kind, "audio")
    |> Jason.Encode.map(opts)
  end
end
