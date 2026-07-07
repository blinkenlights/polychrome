defmodule Octopus.Installation.PanelSlotTest do
  use ExUnit.Case, async: true

  alias Octopus.Hardware.PanelSlot

  test "Prototype installation uses explicit panel slots" do
    assert Octopus.Installation.Prototype.panel_slots() == [
             %PanelSlot{
               controller_id: :polychrome_panel_prototype,
               wiring_id: :serpentine_8x8_bottom_left
             }
           ]
  end

  test "Pixie installation uses vertical serpentine wiring" do
    assert Octopus.Installation.Pixie.panel_slots() == [
             %PanelSlot{
               controller_id: :polychrome_panel_prototype,
               wiring_id: :serpentine_8x8_vertical_bottom_left
             }
           ]
  end

  test "Running Lights installation uses linear strip wiring" do
    assert Octopus.Installation.RunningLights.panel_slots() == [
             %PanelSlot{controller_id: :polychrome_panel_prototype, wiring_id: :linear_strip}
           ]
  end
end
