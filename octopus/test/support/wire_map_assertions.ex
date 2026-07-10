defmodule Octopus.WireMapAssertions do
  @moduledoc false

  import ExUnit.Assertions

  alias Octopus.Hardware
  alias Octopus.Hardware.{Controller, Untangle, WireMap, Wiring}

  @doc """
  Asserts every layout pixel survives wiring + untangle into the correct firmware slot.
  """
  @spec assert_encode_roundtrip!([term()], {pos_integer(), pos_integer()}, Wiring.t(), Controller.t()) ::
          [term()]
  def assert_encode_roundtrip!(values, layout, wiring, controller) do
    {width, height} = layout
    encoded = WireMap.encode_to_firmware(values, layout, wiring, controller)

    assert length(encoded) == controller.max_pixel_count

    for y <- 0..(height - 1), x <- 0..(width - 1) do
      u = x + y * width
      fw = WireMap.firmware_index_for_layout(x, y, layout, wiring, controller)

      assert is_integer(fw),
             "missing firmware index for layout {#{x}, #{y}} with wiring #{wiring.id}"

      assert Enum.at(encoded, fw) == Enum.at(values, u),
             "layout {#{x}, #{y}} (u=#{u}): expected #{inspect(Enum.at(values, u))} " <>
               "at firmware #{fw}, got #{inspect(Enum.at(encoded, fw))}"
    end

    encoded
  end

  @doc """
  Asserts `Untangle.encode_rgb_data/1` round-trips every layout pixel for an installation.
  """
  @spec assert_installation_encode_rgb_roundtrip!(module()) :: :ok
  def assert_installation_encode_rgb_roundtrip!(installation_module) do
    layout = installation_module.panel_layout()
    {width, height} = layout
    pixel_count = width * height
    [%{controller_id: controller_id, wiring_id: wiring_id} | _] =
      Enum.map(installation_module.panel_slots(), fn slot ->
        %{controller_id: slot.controller_id, wiring_id: slot.wiring_id}
      end)

    controller = Hardware.fetch!(controller_id)
    wiring = Hardware.fetch_wiring!(wiring_id)

    data =
      for i <- 0..(pixel_count - 1), into: <<>> do
        <<i, i, i>>
      end

    original_installation = Application.get_env(:octopus, :installation)

    try do
      Application.put_env(:octopus, :installation, installation_module)
      encoded = Untangle.encode_rgb_data(data)

      assert byte_size(encoded) == controller.max_pixel_count * 3

      for y <- 0..(height - 1), x <- 0..(width - 1) do
        u = x + y * width
        fw = WireMap.firmware_index_for_layout(x, y, layout, wiring, controller)

        assert is_integer(fw),
               "missing firmware index for layout {#{x}, #{y}} on #{installation_module}"

        assert binary_part(encoded, fw * 3, 3) == <<u, u, u>>,
               "layout {#{x}, #{y}} (u=#{u}) on #{installation_module}"
      end
    after
      Application.put_env(:octopus, :installation, original_installation)
    end

    :ok
  end

  @doc """
  Asserts firmware slots driving unused strip positions are off for partial panels.
  """
  @spec assert_unused_strips_off!([term()], {pos_integer(), pos_integer()}, Wiring.t(), Controller.t()) ::
          :ok
  def assert_unused_strips_off!(values, layout, wiring, controller) do
    {width, height} = layout
    pixel_count = width * height
    {fw_w, fw_h} = controller.firmware_matrix
    off = off_sample(values)

    encoded = WireMap.encode_to_firmware(values, layout, wiring, controller)

    used_strips =
      MapSet.new(for u <- 0..(pixel_count - 1), do: WireMap.layout_to_strip(u, wiring, width, height))

    for fw <- 0..(controller.max_pixel_count - 1) do
      strip = WireMap.strip_index(fw, fw_w, fw_h)

      if strip not in used_strips do
        assert Enum.at(encoded, fw) == off,
               "firmware #{fw} drives unused strip #{strip}, expected off #{inspect(off)}"
      end
    end

    :ok
  end

  @doc """
  Asserts broadcast `Untangle.encode_w_data/1` round-trips every pixel for each panel
  at the correct firmware_panel_index offset.
  """
  @spec assert_broadcast_encode_w_roundtrip!(module()) :: :ok
  def assert_broadcast_encode_w_roundtrip!(installation_module) do
    slots = installation_module.panel_slots()
    layout = installation_module.panel_layout()
    {width, height} = layout
    pixels_per_panel = width * height

    data =
      for _panel <- 0..(length(slots) - 1),
          i <- 0..(pixels_per_panel - 1),
          into: <<>> do
        <<i>>
      end

    max_firmware_index =
      slots
      |> Enum.map(fn slot -> Hardware.fetch!(slot.controller_id).firmware_panel_index end)
      |> Enum.max()

    original_installation = Application.get_env(:octopus, :installation)

    try do
      Application.put_env(:octopus, :installation, installation_module)
      encoded = Untangle.encode_w_data(data)

      assert byte_size(encoded) == max_firmware_index * 64

      for {slot, logical_slot} <- Enum.with_index(slots) do
        controller = Hardware.fetch!(slot.controller_id)
        wiring = Hardware.fetch_wiring!(slot.wiring_id)
        base_offset = (controller.firmware_panel_index - 1) * 64

        for y <- 0..(height - 1), x <- 0..(width - 1) do
          u = x + y * width
          fw = WireMap.firmware_index_for_layout(x, y, layout, wiring, controller)

          assert is_integer(fw),
                 "missing firmware index for panel #{logical_slot} layout {#{x}, #{y}}"

          global_offset = base_offset + fw

          assert :binary.at(encoded, global_offset) == u,
                 "panel #{logical_slot} layout {#{x}, #{y}} (u=#{u}) at firmware offset #{global_offset}"
        end
      end
    after
      Application.put_env(:octopus, :installation, original_installation)
    end

    :ok
  end

  @doc """
  Asserts broadcast `Untangle.encode_rgb_data/1` round-trips every pixel for each panel
  at the correct firmware_panel_index offset.
  """
  @spec assert_broadcast_encode_rgb_roundtrip!(module()) :: :ok
  def assert_broadcast_encode_rgb_roundtrip!(installation_module) do
    slots = installation_module.panel_slots()
    layout = installation_module.panel_layout()
    {width, height} = layout
    pixels_per_panel = width * height

    data =
      for panel_slot <- 0..(length(slots) - 1), i <- 0..(pixels_per_panel - 1), into: <<>> do
        <<panel_slot, i, 0>>
      end

    max_firmware_index =
      slots
      |> Enum.map(fn slot -> Hardware.fetch!(slot.controller_id).firmware_panel_index end)
      |> Enum.max()

    original_installation = Application.get_env(:octopus, :installation)

    try do
      Application.put_env(:octopus, :installation, installation_module)
      encoded = Untangle.encode_rgb_data(data)

      assert byte_size(encoded) == max_firmware_index * 64 * 3

      for {slot, logical_slot} <- Enum.with_index(slots) do
        controller = Hardware.fetch!(slot.controller_id)
        wiring = Hardware.fetch_wiring!(slot.wiring_id)
        base_offset = (controller.firmware_panel_index - 1) * 64 * 3

        for y <- 0..(height - 1), x <- 0..(width - 1) do
          u = x + y * width
          fw = WireMap.firmware_index_for_layout(x, y, layout, wiring, controller)

        assert is_integer(fw),
               "missing firmware index for panel #{logical_slot} layout {#{x}, #{y}}"

        global_offset = base_offset + fw * 3

        assert binary_part(encoded, global_offset, 3) == <<logical_slot, u, 0>>,
               "panel #{logical_slot} layout {#{x}, #{y}} (u=#{u}) at firmware offset #{global_offset}"
        end
      end
    after
      Application.put_env(:octopus, :installation, original_installation)
    end

    :ok
  end

  defp off_sample([]), do: 0
  defp off_sample([sample | _]), do: off_sample(sample)
  defp off_sample(sample) when is_integer(sample), do: 0
  defp off_sample({_r, _g, _b}), do: {0, 0, 0}
end
