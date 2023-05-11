defmodule Octopus.ColorPalette do
  @moduledoc """
  A ColorPalette is a list of colors.
  """
  alias Octopus.ColorPalette

  defmodule Color do
    defstruct r: 0, g: 0, b: 0
  end

  defstruct colors: []

  @doc """
  Reads from a file exported from lospec.com (use the hex format and save to the palette directory).
  """
  def from_file(name) do
    colors =
      Path.join([:code.priv_dir(:octopus), "color_palettes", "#{name}.hex"])
      |> File.stream!()
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&match?("", &1))
      |> Enum.map(&color_from_hex/1)

    %ColorPalette{colors: colors}
  end

  @doc """
  List available palettes
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
  def from_binary(binary) when is_binary(binary) do
    colors =
      binary
      |> :binary.bin_to_list()
      |> Enum.chunk_every(4)
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

  @doc """
  Applies brightness correction. This is the place were would apply our calibartion once we have it.
  """
  def brightness_correction(%__MODULE__{} = palette) do
    colors =
      palette.colors
      # |> Enum.map(fn %Color{r: r, g: g, b: b} ->
      #   min_value = min(r, min(g, b)) / 2
      #   %Color{r: r - min_value, g: g - min_value, b: b - min_value, w: min_value}
      # end)
      |> Enum.map(fn color ->
        vals =
          color
          |> Map.from_struct()
          |> Enum.map(fn {c, v} -> {c, round(ease(v / 255, 2) * 255)} end)
          |> Enum.into(%{})

        struct(Color, vals)
      end)

    %ColorPalette{colors: colors}
  end

  defp ease(val, index) do
    case index do
      0 -> val
      1 -> Easing.quadratic_in(val)
      2 -> Easing.cubic_in(val)
      3 -> Easing.quartic_in(val)
      4 -> Easing.exponential_in(val)
    end
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
