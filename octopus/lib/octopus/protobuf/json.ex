alias Octopus.Protobuf.Config
alias Octopus.Protobuf.Frame

defimpl Jason.Encoder, for: Config do
  def encode(%Config{} = config, opts) do
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
