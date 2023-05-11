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
  def encode(%Frame{} = frame, opts) do
    frame
    |> Map.from_struct()
    |> Jason.Encode.map(opts)
  end
end
