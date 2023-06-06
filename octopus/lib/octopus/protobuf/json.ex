alias Octopus.Protobuf.FirmwareConfig
alias Octopus.Protobuf.{Frame, RGBFrame}

defimpl Jason.Encoder, for: FirmwareConfig do
  def encode(%FirmwareConfig{} = config, opts) do
    config
    |> Map.from_struct()
    |> Jason.Encode.map(opts)
  end
end

defimpl Jason.Encoder, for: Frame do
  def encode(%Frame{data: data} = frame, opts) do
    %Frame{frame | data: to_charlist(data)}
    |> Map.from_struct()
    |> Jason.Encode.map(opts)
  end
end

defimpl Jason.Encoder, for: RGBFrame do
  def encode(%RGBFrame{data: data} = frame, opts) do
    %RGBFrame{frame | data: :binary.bin_to_list(data)}
    |> Map.from_struct()
    |> Jason.Encode.map(opts)
  end
end
