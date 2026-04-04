alias Octopus.Protobuf.FirmwareConfig
alias Octopus.Protobuf.{RGBFrame, WFrame}

defimpl JSON.Encoder, for: FirmwareConfig do
  def encode(%FirmwareConfig{} = config, encoder) do
    config
    |> Map.from_struct()
    |> encoder.(encoder)
  end
end

defimpl JSON.Encoder, for: RGBFrame do
  def encode(%RGBFrame{data: data} = frame, encoder) do
    %RGBFrame{frame | data: :binary.bin_to_list(data)}
    |> Map.from_struct()
    |> Map.put(:kind, "rgb")
    |> encoder.(encoder)
  end
end

defimpl JSON.Encoder, for: WFrame do
  def encode(%WFrame{data: data} = frame, encoder) do
    %WFrame{frame | data: :binary.bin_to_list(data)}
    |> Map.from_struct()
    |> Map.put(:kind, "w")
    |> encoder.(encoder)
  end
end
