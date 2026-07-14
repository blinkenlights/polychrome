defmodule Octopus.Installation.PanelSlotTest do
  use ExUnit.Case, async: true

  alias Octopus.Hardware.PanelSlot

  test "Prototype installation uses explicit panel slots" do
    assert Octopus.Installation.Prototype.panel_slots() == [
             %PanelSlot{
               controller_id: :pixie,
               port: 1,
               wiring_id: :serpentine_horizontal_bottom_left
             }
           ]
  end

  test "Pixie installation uses vertical serpentine wiring on port 1" do
    assert Octopus.Installation.Pixie.panel_slots() == [
             %PanelSlot{
               controller_id: :pixie,
               port: 1,
               wiring_id: :serpentine_vertical_bottom_left
             }
           ]
  end

  test "Pixie2 installation uses pixie port 2 with 8x8 layout" do
    assert Octopus.Installation.Pixie2.panel_slots() == [
             %PanelSlot{
               controller_id: :pixie,
               port: 2,
               wiring_id: :serpentine_vertical_bottom_left
             }
           ]

    assert Octopus.Installation.Pixie2.panel_layout() == {8, 8}
  end

  test "Woodstock installation uses pixie port 2" do
    assert Octopus.Installation.Woodstock.panel_slots() == [
             %PanelSlot{
               controller_id: :pixie,
               port: 2,
               wiring_id: :serpentine_vertical_bottom_left
             }
           ]

    assert Octopus.Installation.Woodstock.panel_layout() == {2, 32}
  end


  test "Running Lights installation uses vertical serpentine wiring" do
    assert Octopus.Installation.RunningLights.panel_slots() == [
             %PanelSlot{
               controller_id: :pixie,
               port: 1,
               wiring_id: :serpentine_vertical_bottom_left
             }
           ]

    assert Octopus.Installation.RunningLights.panel_layout() == {1, 24}
  end
end
