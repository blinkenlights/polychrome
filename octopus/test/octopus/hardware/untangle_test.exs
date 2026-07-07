defmodule Octopus.Hardware.UntangleTest do
  use ExUnit.Case, async: true

  alias Octopus.Hardware
  alias Octopus.Hardware.PanelSlot
  alias Octopus.Hardware.Untangle
  alias Octopus.Hardware.WireMap

  @installation_opts [
    panel_slots: [
      %PanelSlot{controller_id: :polychrome_panel_1, wiring_id: :serpentine_8x8_bottom_left},
      %PanelSlot{controller_id: :polychrome_panel_3, wiring_id: :serpentine_8x8_bottom_left},
      %PanelSlot{controller_id: :polychrome_panel_2, wiring_id: :serpentine_8x8_bottom_left}
    ],
    panels: [:polychrome_panel_1, :polychrome_panel_3, :polychrome_panel_2],
    network_config: [mode: :broadcast]
  ]

  test "logical_panel_number maps firmware index to logical slot" do
    assert Untangle.logical_panel_number(@installation_opts, 1) == 1
    assert Untangle.logical_panel_number(@installation_opts, 2) == 3
    assert Untangle.logical_panel_number(@installation_opts, 3) == 2
    assert Untangle.logical_panel_number(@installation_opts, 99) == nil
  end

  test "logical_panel_id returns zero-based slot" do
    assert Untangle.logical_panel_id(@installation_opts, 3) == 1
  end

  test "encode_rgb_data for vertical wiring places bottom-left layout at firmware strip 0" do
    data =
      for i <- 0..63, into: <<>> do
        <<i, i, i>>
      end

    original_installation = Application.get_env(:octopus, :installation)

    try do
      Application.put_env(:octopus, :installation, Octopus.Installation.Pixie)

      encoded = Untangle.encode_rgb_data(data)
      assert byte_size(encoded) == 64 * 3

      bottom_left_firmware_index =
        WireMap.firmware_index_for_layout(
          0,
          7,
          {8, 8},
          Hardware.fetch_wiring!(:serpentine_8x8_vertical_bottom_left),
          Hardware.fetch!(:polychrome_panel_prototype)
        )

      assert binary_part(encoded, bottom_left_firmware_index * 3, 3) == <<56, 56, 56>>
    after
      Application.put_env(:octopus, :installation, original_installation)
    end
  end
end
