defmodule Octopus.TestInstallations.BroadcastTwoPanels do
  use Octopus.Installation,
    arrangement: :linear,
    panels: [
      [controller: :polychrome_01, wiring: :serpentine_horizontal_bottom_left],
      [controller: :polychrome_02, wiring: :serpentine_horizontal_bottom_left]
    ],
    panel_layout: {8, 8},
    num_buttons: 0,
    num_joysticks: 0,
    panel_gap: 0,
    global_speed: 1.0,
    location: :auto,
    auto_brightness: false,
    network_config: [
      mode: :broadcast
    ],
    simulator_layouts: [
      [
        name: "Broadcast Two Panels",
        mode: "generic",
        pixel_size: {64, 64}
      ]
    ]
end

defmodule Octopus.Hardware.UntangleTest do
  use ExUnit.Case, async: true

  alias Octopus.Hardware.PanelSlot
  alias Octopus.Hardware.Untangle
  alias Octopus.WireMapAssertions

  @installation_opts [
    panel_slots: [
      %PanelSlot{
        controller_id: :polychrome_01,
        wiring_id: :serpentine_horizontal_bottom_left
      },
      %PanelSlot{
        controller_id: :polychrome_03,
        wiring_id: :serpentine_horizontal_bottom_left
      },
      %PanelSlot{
        controller_id: :polychrome_02,
        wiring_id: :serpentine_horizontal_bottom_left
      }
    ],
    panels: [:polychrome_01, :polychrome_03, :polychrome_02],
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

  test "encode_rgb_data round-trips all pixels for Prototype horizontal 8x8" do
    WireMapAssertions.assert_installation_encode_rgb_roundtrip!(Octopus.Installation.Prototype)
  end

  test "encode_rgb_data round-trips all pixels for Pixie vertical 8x8" do
    WireMapAssertions.assert_installation_encode_rgb_roundtrip!(Octopus.Installation.Pixie)
  end

  test "encode_rgb_data round-trips all pixels for Running Lights vertical 1x24" do
    WireMapAssertions.assert_installation_encode_rgb_roundtrip!(Octopus.Installation.RunningLights)
  end

  test "encode_rgb_data broadcast round-trips each panel at firmware_panel_index offset" do
    WireMapAssertions.assert_broadcast_encode_rgb_roundtrip!(Octopus.TestInstallations.BroadcastTwoPanels)
  end

  test "encode_w_data broadcast round-trips each panel at firmware_panel_index offset" do
    WireMapAssertions.assert_broadcast_encode_w_roundtrip!(Octopus.TestInstallations.BroadcastTwoPanels)
  end
end
