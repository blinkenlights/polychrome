defmodule Octopus.Hardware.WireMap do
  @moduledoc """
  Maps between panel layout indices and firmware logical pixel indices.

  Ports the serpentine matrix cell assignment from `Display.cpp` `map_index/1`
  (excluding `SKIP_LEDS` ×2). Layout indices use top-left row-major order
  (mixer / canvas convention).
  """

  @default_width 8
  @default_height 8

  @doc """
  Returns the serpentine strip index for firmware logical index `i`
  (matches C++ `map_index` without `SKIP_LEDS`).
  """
  @spec strip_index(non_neg_integer(), pos_integer(), pos_integer()) :: non_neg_integer()
  def strip_index(i, width \\ @default_width, height \\ @default_height) do
    x = rem(i, width)
    y = height - 1 - div(i, width)

    if rem(y, 2) == 0 do
      y * width + x
    else
      y * width + (width - x - 1)
    end
  end

  @doc """
  Maps a top-left row-major layout index to the firmware logical index.
  """
  @spec layout_to_firmware_index(non_neg_integer(), pos_integer(), pos_integer()) ::
          non_neg_integer()
  def layout_to_firmware_index(u, width \\ @default_width, height \\ @default_height) do
    x = rem(u, width)
    y_top = div(u, width)
    y_bottom = height - 1 - y_top
    x + y_bottom * width
  end

  @doc """
  Maps a firmware logical index to top-left row-major layout index.
  """
  @spec firmware_to_layout_index(non_neg_integer(), pos_integer(), pos_integer()) ::
          non_neg_integer()
  def firmware_to_layout_index(i, width \\ @default_width, height \\ @default_height) do
    x = rem(i, width)
    y_bottom = div(i, width)
    y_top = height - 1 - y_bottom
    x + y_top * width
  end

  @doc """
  Reorders layout-ordered strip values (0..N-1 left-to-right) into firmware buffer
  order so on-device `map_index/1` lights the intended strip positions.
  """
  @spec apply_strip_inverse([term()], pos_integer(), pos_integer(), pos_integer()) :: [term()]
  def apply_strip_inverse(values, pixel_count \\ 64, width \\ @default_width, height \\ @default_height) do
    for i <- 0..(pixel_count - 1) do
      strip = strip_index(i, width, height)
      Enum.at(values, strip)
    end
  end

  @doc """
  Returns the firmware buffer index that drives a given physical strip position.
  """
  @spec firmware_index_for_strip(non_neg_integer(), pos_integer(), pos_integer(), pos_integer()) ::
          non_neg_integer() | nil
  def firmware_index_for_strip(strip, pixel_count \\ 64, width \\ @default_width, height \\ @default_height) do
    Enum.find(0..(pixel_count - 1), fn i ->
      strip_index(i, width, height) == strip
    end)
  end

  @doc """
  Reorders `values` from layout order into firmware logical index order.
  """
  @spec apply_inverse([term()], pos_integer(), pos_integer(), pos_integer()) :: [term()]
  def apply_inverse(values, pixel_count \\ 64, width \\ @default_width, height \\ @default_height) do
    for i <- 0..(pixel_count - 1) do
      layout_u = firmware_to_layout_index(i, width, height)
      Enum.at(values, layout_u)
    end
  end

  @doc """
  Reorders RGB triples in a binary from layout order to firmware logical index order.
  """
  @spec apply_inverse_rgb(binary(), pos_integer(), pos_integer(), pos_integer()) :: binary()
  def apply_inverse_rgb(data, pixel_count \\ 64, width \\ @default_width, height \\ @default_height) do
    pixels =
      for <<r, g, b <- data>> do
        {r, g, b}
      end

    pixels
    |> apply_inverse(pixel_count, width, height)
    |> Enum.flat_map(fn
      {r, g, b} -> [r, g, b]
      gray when is_integer(gray) -> [gray, gray, gray]
    end)
    |> IO.iodata_to_binary()
  end

  @doc """
  Reorders grayscale bytes from layout order to firmware logical index order.
  """
  @spec apply_inverse_w(binary(), pos_integer(), pos_integer(), pos_integer()) :: binary()
  def apply_inverse_w(data, pixel_count \\ 64, width \\ @default_width, height \\ @default_height) do
    bytes = for <<b <- data>>, do: b

    bytes
    |> apply_inverse(pixel_count, width, height)
    |> IO.iodata_to_binary()
  end
end
