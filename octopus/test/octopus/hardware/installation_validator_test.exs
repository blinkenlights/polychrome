defmodule Octopus.Hardware.InstallationValidatorTest do
  use ExUnit.Case, async: true

  alias Octopus.Hardware
  alias Octopus.Hardware.InstallationValidator
  alias Octopus.Hardware.InstallationValidator.Error
  alias Octopus.Hardware.PanelSlot
  alias Octopus.Hardware.Wiring

  test "accepts Nation2025-style panel list" do
    assert :ok =
             InstallationValidator.validate!(
               [
                 panel_slots: [
                   %PanelSlot{
                     controller_id: :polychrome_panel_1,
                     wiring_id: :serpentine_horizontal_bottom_left
                   },
                   %PanelSlot{
                     controller_id: :polychrome_panel_2,
                     wiring_id: :serpentine_horizontal_bottom_left
                   }
                 ],
                 panels: [:polychrome_panel_1, :polychrome_panel_2],
                 panel_layout: {8, 8},
                 network_config: [mode: :broadcast]
               ],
               Hardware.registry()
             )
  end

  test "raises on unknown controller id" do
    assert_raise Error, ~r/unknown controller id/, fn ->
      InstallationValidator.validate!(
        [
          panel_slots: [
            %PanelSlot{
              controller_id: :not_a_real_panel,
              wiring_id: :serpentine_horizontal_bottom_left
            }
          ],
          panels: [:not_a_real_panel],
          panel_layout: {8, 8},
          network_config: [mode: :broadcast]
        ],
        Hardware.registry()
      )
    end
  end

  test "raises on unknown wiring id" do
    assert_raise Error, ~r/unknown wiring id/, fn ->
      InstallationValidator.validate!(
        [
          panel_slots: [
            %PanelSlot{controller_id: :polychrome_panel_1, wiring_id: :not_a_real_wiring}
          ],
          panels: [:polychrome_panel_1],
          panel_layout: {8, 8},
          network_config: [mode: :broadcast]
        ],
        Hardware.registry()
      )
    end
  end

  test "raises when fixed wiring matrix does not match panel_layout" do
    wiring_registry =
      Map.put(
        Hardware.wiring_registry(),
        :fixed_8x8,
        %Wiring{id: :fixed_8x8, matrix: {8, 8}, type: :serpentine_horizontal_bottom_left}
      )

    assert_raise Error, ~r/does not match installation panel_layout/, fn ->
      InstallationValidator.validate!(
        [
          panel_slots: [
            %PanelSlot{controller_id: :polychrome_panel_prototype, wiring_id: :fixed_8x8}
          ],
          panels: [:polychrome_panel_prototype],
          panel_layout: {1, 64},
          network_config: [mode: :individual]
        ],
        Hardware.registry(),
        wiring_registry
      )
    end
  end

  test "raises when panel_layout pixel count exceeds controller maximum" do
    assert_raise Error, ~r/exceeds controller/, fn ->
      InstallationValidator.validate!(
        [
          panel_slots: [
            %PanelSlot{
              controller_id: :polychrome_panel_prototype,
              wiring_id: :serpentine_vertical_bottom_left
            }
          ],
          panels: [:polychrome_panel_prototype],
          panel_layout: {8, 9},
          network_config: [mode: :individual]
        ],
        Hardware.registry()
      )
    end
  end

  test "accepts panel_layout with fewer pixels than controller maximum" do
    assert :ok =
             InstallationValidator.validate!(
               [
                 panel_slots: [
                   %PanelSlot{
                     controller_id: :polychrome_panel_prototype,
                     wiring_id: :serpentine_vertical_bottom_left
                   }
                 ],
                 panels: [:polychrome_panel_prototype],
                 panel_layout: {1, 24},
                 network_config: [mode: :individual]
               ],
               Hardware.registry()
             )
  end

  test "accepts vertical serpentine with vertical panel_layout" do
    assert :ok =
             InstallationValidator.validate!(
               [
                 panel_slots: [
                   %PanelSlot{
                     controller_id: :polychrome_panel_prototype,
                     wiring_id: :serpentine_vertical_bottom_left
                   }
                 ],
                 panels: [:polychrome_panel_prototype],
                 panel_layout: {1, 64},
                 network_config: [mode: :individual]
               ],
               Hardware.registry()
             )
  end

  test "raises on duplicate firmware_panel_index in broadcast mode" do
    assert_raise Error, ~r/broadcast installation cannot include multiple panels/, fn ->
      InstallationValidator.validate!(
        [
          panel_slots: [
            %PanelSlot{
              controller_id: :polychrome_panel_1,
              wiring_id: :serpentine_horizontal_bottom_left
            },
            %PanelSlot{
              controller_id: :polychrome_panel_prototype,
              wiring_id: :serpentine_horizontal_bottom_left
            }
          ],
          panels: [:polychrome_panel_1, :polychrome_panel_prototype],
          panel_layout: {8, 8},
          network_config: [mode: :broadcast]
        ],
        Hardware.registry()
      )
    end
  end

  test "allows duplicate firmware_panel_index for single-panel individual setup" do
    assert :ok =
             InstallationValidator.validate!(
               [
                 panel_slots: [
                   %PanelSlot{
                     controller_id: :polychrome_panel_prototype,
                     wiring_id: :serpentine_horizontal_bottom_left
                   }
                 ],
                 panels: [:polychrome_panel_prototype],
                 panel_layout: {8, 8},
                 network_config: [mode: :individual]
               ],
               Hardware.registry()
             )
  end

  test "raises when panel_layout does not match panel_type reference matrix" do
    assert_raise Error, ~r/does not match panel_type/, fn ->
      InstallationValidator.validate!(
        [
          panel_type: :woodstock,
          panel_layout: {8, 8},
          panel_slots: [],
          panels: [],
          network_config: [mode: :broadcast]
        ],
        Hardware.registry()
      )
    end
  end

  test "accepts matching panel_type and panel_layout" do
    assert :ok =
             InstallationValidator.validate!(
               [
                 panel_type: :polychrome,
                 panel_layout: {8, 8},
                 panel_slots: [],
                 panels: [],
                 network_config: [mode: :broadcast]
               ],
               Hardware.registry()
             )
  end
end
