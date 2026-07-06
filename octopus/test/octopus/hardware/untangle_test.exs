defmodule Octopus.Hardware.UntangleTest do
  use ExUnit.Case, async: true

  alias Octopus.Hardware.Untangle

  @installation_opts [
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
end
