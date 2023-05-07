alias Sim.Protobuf.Config

defimpl Jason.Encoder, for: Config do
  def encode(%Config{} = config, opts) do
    config
    |> Map.from_struct()
    |> Map.update(:color_palette, <<>>, fn palette ->
      palette |> :binary.bin_to_list() |> Enum.chunk_every(4)
    end)
    |> Jason.Encode.map(opts)
  end
end
