defmodule Octopus.Hardware.Untangle do
  @moduledoc """
  Encodes mixer frames for firmware panel order and maps inbound sensor indices.
  """

  alias Octopus.Hardware
  alias Octopus.Hardware.{Panel, WireMap}
  alias Octopus.Installation
  alias Octopus.Protobuf.{RGBFrame, WFrame}

  @doc """
  Applies wire-map reordering and logical→firmware panel placement to an RGB frame.
  """
  @spec encode_rgb_frame(RGBFrame.t()) :: RGBFrame.t()
  def encode_rgb_frame(%RGBFrame{data: data} = frame) do
    %{frame | data: encode_rgb_data(data)}
  end

  @doc """
  Applies wire-map reordering and logical→firmware panel placement to a W frame.
  """
  @spec encode_w_frame(WFrame.t()) :: WFrame.t()
  def encode_w_frame(%WFrame{data: data} = frame) do
    %{frame | data: encode_w_data(data)}
  end

  @doc """
  Encodes RGB pixel data for the current installation.
  """
  @spec encode_rgb_data(binary()) :: binary()
  def encode_rgb_data(data) when is_binary(data) do
    panel_ids = Installation.panels()

    if panel_ids == [] do
      data
    else
      pixels_per_panel = Installation.panel_width() * Installation.panel_height()
      bytes_per_panel = pixels_per_panel * 3
      layout = Installation.panel_layout()

      case encode_mode() do
        :individual_single ->
          panel_id = hd(panel_ids)
          panel = Hardware.fetch!(panel_id)
          source = binary_part(data, 0, min(bytes_per_panel, byte_size(data)))

          source
          |> split_panel_rgb(pixels_per_panel)
          |> encode_panel_pixels(panel, layout)
          |> pixels_to_rgb_binary()

        :broadcast ->
          max_index = max_firmware_panel_index(panel_ids)
          buffer = :binary.copy(<<0>>, max_index * 64 * 3)

          panel_ids
          |> Enum.with_index()
          |> Enum.reduce(buffer, fn {panel_id, logical_slot}, acc ->
            panel = Hardware.fetch!(panel_id)
            source_offset = logical_slot * bytes_per_panel
            slice = binary_part(data, source_offset, bytes_per_panel)

            encoded =
              slice
              |> split_panel_rgb(pixels_per_panel)
              |> encode_panel_pixels(panel, layout)
              |> pixels_to_rgb_binary()

            dest_offset = (panel.firmware_panel_index - 1) * 64 * 3
            place_binary(acc, dest_offset, encoded)
          end)
      end
    end
  end

  @doc """
  Encodes W pixel data for the current installation.
  """
  @spec encode_w_data(binary()) :: binary()
  def encode_w_data(data) when is_binary(data) do
    panel_ids = Installation.panels()

    if panel_ids == [] do
      data
    else
      pixels_per_panel = Installation.panel_width() * Installation.panel_height()
      layout = Installation.panel_layout()

      case encode_mode() do
        :individual_single ->
          panel_id = hd(panel_ids)
          panel = Hardware.fetch!(panel_id)
          source = binary_part(data, 0, min(pixels_per_panel, byte_size(data)))

          source
          |> split_panel_w(pixels_per_panel)
          |> encode_panel_pixels(panel, layout)
          |> IO.iodata_to_binary()

        :broadcast ->
          max_index = max_firmware_panel_index(panel_ids)
          buffer = :binary.copy(<<0>>, max_index * 64)

          panel_ids
          |> Enum.with_index()
          |> Enum.reduce(buffer, fn {panel_id, logical_slot}, acc ->
            panel = Hardware.fetch!(panel_id)
            source_offset = logical_slot * pixels_per_panel
            slice = binary_part(data, source_offset, pixels_per_panel)

            encoded =
              slice
              |> split_panel_w(pixels_per_panel)
              |> encode_panel_pixels(panel, layout)
              |> IO.iodata_to_binary()

            dest_offset = panel.firmware_panel_index - 1
            place_binary(acc, dest_offset, encoded)
          end)
      end
    end
  end

  @doc """
  Maps firmware panel index to 1-based logical panel number for apps.
  """
  @spec logical_panel_number(module() | keyword(), pos_integer()) :: pos_integer() | nil
  def logical_panel_number(installation \\ Installation, firmware_panel_index)
      when is_integer(firmware_panel_index) and firmware_panel_index > 0 do
    case logical_panel_id(installation, firmware_panel_index) do
      nil -> nil
      id -> id + 1
    end
  end

  @doc """
  Maps firmware panel index to 0-based logical panel slot.
  """
  @spec logical_panel_id(module() | keyword(), pos_integer()) :: non_neg_integer() | nil
  def logical_panel_id(installation \\ Installation, firmware_panel_index)
      when is_integer(firmware_panel_index) and firmware_panel_index > 0 do
    panels =
      case installation do
        module when is_atom(module) -> module.panels()
        opts when is_list(opts) -> Keyword.fetch!(opts, :panels)
      end

    panels
    |> Enum.with_index()
    |> Enum.find_value(fn {panel_id, logical_slot} ->
      panel = Hardware.fetch!(panel_id)

      if panel.firmware_panel_index == firmware_panel_index do
        logical_slot
      end
    end)
  end

  defp encode_mode do
    network_config = Installation.network_config()
    mode = Keyword.get(network_config, :mode, :broadcast)

    if mode == :individual and Installation.num_panels() == 1 do
      :individual_single
    else
      :broadcast
    end
  end

  defp encode_panel_pixels(values, %Panel{wire_map: :identity}, _layout), do: values

  defp encode_panel_pixels(values, %Panel{pixel_count: pixel_count, matrix: {w, h}}, {width, 1})
       when width == pixel_count do
    WireMap.apply_strip_inverse(values, pixel_count, w, h)
  end

  defp encode_panel_pixels(values, %Panel{pixel_count: pixel_count, matrix: {w, h}} = _panel, layout) do
    if layout == {8, 8} or layout == {w, h} do
      WireMap.apply_inverse(values, pixel_count, w, h)
    else
      values
    end
  end

  defp split_panel_rgb(data, pixel_count) do
    pixels = for <<r, g, b <- data>>, do: {r, g, b}
    Enum.take(pixels, pixel_count)
  end

  defp split_panel_w(data, pixel_count) do
    bytes = for <<b <- data>>, do: b
    Enum.take(bytes, pixel_count)
  end

  defp pixels_to_rgb_binary(values) do
    values
    |> Enum.flat_map(fn
      {r, g, b} -> [r, g, b]
      b when is_integer(b) -> [b]
    end)
    |> IO.iodata_to_binary()
  end

  defp place_binary(buffer, offset, slice) when is_binary(slice) do
    prefix = binary_part(buffer, 0, offset)
    suffix_size = byte_size(buffer) - offset - byte_size(slice)
    suffix = if suffix_size > 0, do: binary_part(buffer, offset + byte_size(slice), suffix_size), else: <<>>
    prefix <> slice <> suffix
  end

  defp max_firmware_panel_index(panel_ids) do
    panel_ids
    |> Enum.map(&Hardware.fetch!(&1).firmware_panel_index)
    |> Enum.max()
  end
end
