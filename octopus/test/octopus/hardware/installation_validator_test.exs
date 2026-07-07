defmodule Octopus.Hardware.InstallationValidatorTest do
  use ExUnit.Case, async: true

  alias Octopus.Hardware
  alias Octopus.Hardware.InstallationValidator
  alias Octopus.Hardware.InstallationValidator.Error
  alias Octopus.Hardware.PanelSlot

  test "accepts Nation2025-style panel list" do
    assert :ok =
             InstallationValidator.validate!(
               [
                 panel_slots: [
                   %PanelSlot{controller_id: :polychrome_panel_1, wiring_id: :serpentine_8x8_bottom_left},
                   %PanelSlot{controller_id: :polychrome_panel_2, wiring_id: :serpentine_8x8_bottom_left}
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
            %PanelSlot{controller_id: :not_a_real_panel, wiring_id: :serpentine_8x8_bottom_left}
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

  test "raises when wiring matrix does not match panel_layout" do
    assert_raise Error, ~r/does not match installation panel_layout/, fn ->
      InstallationValidator.validate!(
        [
          panel_slots: [
            %PanelSlot{controller_id: :polychrome_panel_prototype, wiring_id: :linear_strip}
          ],
          panels: [:polychrome_panel_prototype],
          panel_layout: {8, 8},
          network_config: [mode: :individual]
        ],
        Hardware.registry()
      )
    end
  end

  test "raises on duplicate firmware_panel_index in broadcast mode" do
    assert_raise Error, ~r/broadcast installation cannot include multiple panels/, fn ->
      InstallationValidator.validate!(
        [
          panel_slots: [
            %PanelSlot{controller_id: :polychrome_panel_1, wiring_id: :serpentine_8x8_bottom_left},
            %PanelSlot{controller_id: :polychrome_panel_prototype, wiring_id: :serpentine_8x8_bottom_left}
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
                     wiring_id: :serpentine_8x8_bottom_left
                   }
                 ],
                 panels: [:polychrome_panel_prototype],
                 panel_layout: {8, 8},
                 network_config: [mode: :individual]
               ],
               Hardware.registry()
             )
  end
end
