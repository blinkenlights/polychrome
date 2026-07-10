defmodule Octopus.Hardware.WireMap do
  @moduledoc """
  Maps between panel layout indices, physical strip positions, and firmware buffer indices.

  Ports the serpentine matrix cell assignment from `Display.cpp` `map_index/1`
  (excluding `SKIP_LEDS` ×2). Layout indices use top-left row-major order
  (mixer / canvas convention).
  """

  alias Octopus.Hardware.{Controller, Wiring}

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
  Maps a top-left row-major layout index to the firmware logical index
  for horizontal serpentine wiring.
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
  Maps a firmware logical index to top-left row-major layout index
  for horizontal serpentine wiring.
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
  Maps a top-left row-major layout index to physical strip position
  for the given wiring type.
  """
  @spec layout_to_strip(non_neg_integer(), Wiring.t(), pos_integer(), pos_integer()) ::
          non_neg_integer()
  def layout_to_strip(u, %Wiring{type: type}, width, height) do
    case type do
      :serpentine_horizontal_bottom_left ->
        horizontal_layout_to_strip(u, width, height)

      :serpentine_vertical_bottom_left ->
        vertical_layout_to_strip(u, width, height)
    end
  end

  @doc """
  Maps a physical strip position to top-left row-major layout index
  for the given wiring type.
  """
  @spec strip_to_layout(non_neg_integer(), Wiring.t(), pos_integer(), pos_integer()) ::
          non_neg_integer()
  def strip_to_layout(strip, %Wiring{type: type}, width, height) do
    case type do
      :serpentine_horizontal_bottom_left ->
        horizontal_strip_to_layout(strip, width, height)

      :serpentine_vertical_bottom_left ->
        vertical_strip_to_layout(strip, width, height)
    end
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
  Reorders `values` from layout order into firmware logical index order
  for horizontal serpentine wiring.
  """
  @spec apply_inverse([term()], pos_integer(), pos_integer(), pos_integer()) :: [term()]
  def apply_inverse(values, pixel_count \\ 64, width \\ @default_width, height \\ @default_height) do
    for i <- 0..(pixel_count - 1) do
      layout_u = firmware_to_layout_index(i, width, height)
      Enum.at(values, layout_u)
    end
  end

  @doc """
  Encodes layout-ordered pixel values for a controller and panel wiring setup.

  Two-step pipeline:

  1. **Wiring** — map each layout index to a physical strip position via the panel
     wiring (`layout_to_strip/4`).
  2. **Untangle** — reorder strip-indexed values into firmware buffer order via
     `apply_strip_inverse/4`, inverting the controller's `strip_index/3` map.
  """
  @spec encode_to_firmware([term()], {pos_integer(), pos_integer()}, Wiring.t(), Controller.t()) ::
          [term()]
  def encode_to_firmware(values, {width, height}, %Wiring{} = wiring, %Controller{} = controller) do
    pixel_count = width * height
    max_pixels = controller.max_pixel_count
    {fw_w, fw_h} = controller.firmware_matrix
    off = off_value(values)

    strip_values =
      for _ <- 0..(max_pixels - 1), do: off

    strip_values =
      Enum.reduce(0..(pixel_count - 1), strip_values, fn u, acc ->
        strip = layout_to_strip(u, wiring, width, height)
        List.replace_at(acc, strip, Enum.at(values, u))
      end)

    apply_strip_inverse(strip_values, max_pixels, fw_w, fw_h)
  end

  defp off_value([]), do: 0
  defp off_value([sample | _]), do: off_value(sample)
  defp off_value(sample) when is_integer(sample), do: 0
  defp off_value({_r, _g, _b}), do: {0, 0, 0}

  @doc """
  Returns the firmware buffer index that lights a given layout coordinate.
  """
  @spec firmware_index_for_layout(
          non_neg_integer(),
          non_neg_integer(),
          {pos_integer(), pos_integer()},
          Wiring.t(),
          Controller.t()
        ) :: non_neg_integer() | nil
  def firmware_index_for_layout(x, y, {width, height}, wiring, controller) do
    layout_u = x + y * width
    strip = layout_to_strip(layout_u, wiring, width, height)
    {fw_w, fw_h} = controller.firmware_matrix

    firmware_index_for_strip(strip, controller.max_pixel_count, fw_w, fw_h)
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

  defp horizontal_layout_to_strip(u, width, height) do
    x = rem(u, width)
    y_top = div(u, width)
    y_bottom = height - 1 - y_top

    if rem(y_bottom, 2) == 0 do
      y_bottom * width + x
    else
      y_bottom * width + (width - x - 1)
    end
  end

  defp horizontal_strip_to_layout(strip, width, height) do
    y_bottom = div(strip, width)
    y_top = height - 1 - y_bottom

    x =
      if rem(y_bottom, 2) == 0 do
        rem(strip, width)
      else
        width - 1 - rem(strip, width)
      end

    x + y_top * width
  end

  defp vertical_layout_to_strip(u, width, height) do
    x = rem(u, width)
    y_top = div(u, width)

    if rem(x, 2) == 0 do
      x * height + (height - 1 - y_top)
    else
      x * height + y_top
    end
  end

  defp vertical_strip_to_layout(strip, width, height) do
    x = div(strip, height)
    offset = rem(strip, height)

    y_top =
      if rem(x, 2) == 0 do
        height - 1 - offset
      else
        offset
      end

    x + y_top * width
  end
end
