defmodule Octopus.Hardware.Untangle do
  @moduledoc """
  Encodes mixer frames for firmware panel order and maps inbound sensor indices.
  """

  alias Octopus.Hardware
  alias Octopus.Hardware.{PanelSlot, WireMap}
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
    panel_slots = Installation.panel_slots()

    if panel_slots == [] do
      data
    else
      pixels_per_panel = Installation.panel_width() * Installation.panel_height()
      bytes_per_panel = pixels_per_panel * 3
      layout = Installation.panel_layout()

      case encode_mode() do
        :individual_single ->
          slot = hd(panel_slots)
          source = binary_part(data, 0, min(bytes_per_panel, byte_size(data)))

          source
          |> split_panel_rgb(pixels_per_panel)
          |> encode_panel_pixels(slot, layout)
          |> pixels_to_rgb_binary()

        :broadcast ->
          max_index = max_firmware_panel_index(panel_slots)
          buffer = :binary.copy(<<0>>, max_index * 64 * 3)

          panel_slots
          |> Enum.with_index()
          |> Enum.reduce(buffer, fn {slot, logical_slot}, acc ->
            source_offset = logical_slot * bytes_per_panel
            slice = binary_part(data, source_offset, bytes_per_panel)

            encoded =
              slice
              |> split_panel_rgb(pixels_per_panel)
              |> encode_panel_pixels(slot, layout)
              |> pixels_to_rgb_binary()

            controller = Hardware.fetch!(slot.controller_id)
            dest_offset = (controller.firmware_panel_index - 1) * 64 * 3
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
    panel_slots = Installation.panel_slots()

    if panel_slots == [] do
      data
    else
      pixels_per_panel = Installation.panel_width() * Installation.panel_height()
      layout = Installation.panel_layout()

      case encode_mode() do
        :individual_single ->
          slot = hd(panel_slots)
          source = binary_part(data, 0, min(pixels_per_panel, byte_size(data)))

          source
          |> split_panel_w(pixels_per_panel)
          |> encode_panel_pixels(slot, layout)
          |> IO.iodata_to_binary()

        :broadcast ->
          max_index = max_firmware_panel_index(panel_slots)
          buffer = :binary.copy(<<0>>, max_index * 64)

          panel_slots
          |> Enum.with_index()
          |> Enum.reduce(buffer, fn {slot, logical_slot}, acc ->
            source_offset = logical_slot * pixels_per_panel
            slice = binary_part(data, source_offset, pixels_per_panel)

            encoded =
              slice
              |> split_panel_w(pixels_per_panel)
              |> encode_panel_pixels(slot, layout)
              |> IO.iodata_to_binary()

            controller = Hardware.fetch!(slot.controller_id)
            dest_offset = controller.firmware_panel_index - 1
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
    slots =
      case installation do
        module when is_atom(module) -> module.panel_slots()
        opts when is_list(opts) -> Keyword.fetch!(opts, :panel_slots)
      end

    slots
    |> Enum.with_index()
    |> Enum.find_value(fn {%PanelSlot{controller_id: controller_id}, logical_slot} ->
      controller = Hardware.fetch!(controller_id)

      if controller.firmware_panel_index == firmware_panel_index do
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

  defp encode_panel_pixels(values, %PanelSlot{controller_id: controller_id, wiring_id: wiring_id}, layout) do
    controller = Hardware.fetch!(controller_id)
    wiring = Hardware.fetch_wiring!(wiring_id)
    WireMap.encode_to_firmware(values, layout, wiring, controller)
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

  defp max_firmware_panel_index(panel_slots) do
    panel_slots
    |> Enum.map(fn %PanelSlot{controller_id: id} -> Hardware.fetch!(id).firmware_panel_index end)
    |> Enum.max()
  end
end
