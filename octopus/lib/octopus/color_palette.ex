defmodule Octopus.ColorPalette do
  @moduledoc """
  A ColorPalette is a list of RGB colors.
  """

  alias Octopus.ColorPalette

  defmodule Color do
    defstruct r: 0, g: 0, b: 0
  end

  defstruct colors: []

  @doc """
  Loads a color palette from a file. Palettes are cached lazily, so the file system is only accessed on first read.

  The palette files are exported from lospec.com (use the hex format and save to the priv/color_palette directory).
  """
  def load(name) do
    Cachex.fetch!(__MODULE__, name, fn _ ->
      path = Path.join([:code.priv_dir(:octopus), "color_palettes", "#{name}.hex"])

      if File.exists?(path) do
        colors =
          File.stream!(path)
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&match?("", &1))
          |> Enum.map(&color_from_hex/1)

        {:commit, %__MODULE__{colors: colors}}
      else
        raise "Palette #{path} not found"
      end
    end)
  end

  @doc """
  List available palettes. Palettes are loaded from the priv/color_palette directory.
  """
  def list_available() do
    Path.join([:code.priv_dir(:octopus), "color_palettes"])
    |> File.ls!()
    |> Enum.filter(&String.ends_with?(&1, ".hex"))
    |> Enum.map(fn file_name -> String.replace(file_name, ".hex", "") end)
  end

  @doc """
  Reads from a binary in the protobuf format [r, g, b, r, g, b, ...].
  """
  def from_binary(io_list) when is_list(io_list) do
    io_list
    |> IO.iodata_to_binary()
    |> from_binary()
  end

  def from_binary(binary) when is_binary(binary) do
    colors =
      binary
      |> :binary.bin_to_list()
      |> Enum.chunk_every(3)
      |> Enum.map(fn [r, g, b] -> %Color{r: r, g: g, b: b} end)

    %ColorPalette{colors: colors}
  end

  @doc """
  Writes a binary in the protobuf format [r, g, b, r, g, b, ...].
  """
  def to_binary(%__MODULE__{colors: colors} = _palette) do
    colors
    |> Enum.map(fn %Color{r: r, g: g, b: b} -> [r, g, b] end)
    |> IO.iodata_to_binary()
  end

  defp color_from_hex(<<r::binary-size(2), g::binary-size(2), b::binary-size(2)>>) do
    %Color{
      r: Integer.parse(r, 16) |> elem(0),
      g: Integer.parse(g, 16) |> elem(0),
      b: Integer.parse(b, 16) |> elem(0)
    }
  end

  defimpl Jason.Encoder, for: __MODULE__ do
    def encode(%Octopus.ColorPalette{colors: colors}, opts) do
      colors
      |> Enum.map(fn %Color{r: r, g: g, b: b} -> [r, g, b] end)
      |> Jason.Encode.list(opts)
    end
  end
end
