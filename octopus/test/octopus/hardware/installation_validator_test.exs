defmodule Octopus.Hardware.InstallationValidatorTest do
  use ExUnit.Case, async: true

  alias Octopus.Hardware
  alias Octopus.Hardware.InstallationValidator
  alias Octopus.Hardware.InstallationValidator.Error

  test "accepts Nation2025-style panel list" do
    assert :ok =
             InstallationValidator.validate!(
               [
                 panels: [
                   :polychrome_panel_1,
                   :polychrome_panel_2
                 ],
                 network_config: [mode: :broadcast]
               ],
               Hardware.registry()
             )
  end

  test "raises on unknown panel id" do
    assert_raise Error, ~r/unknown panel id/, fn ->
      InstallationValidator.validate!(
        [panels: [:not_a_real_panel], network_config: [mode: :broadcast]],
        Hardware.registry()
      )
    end
  end

  test "raises on duplicate firmware_panel_index in broadcast mode" do
    assert_raise Error, ~r/broadcast installation cannot include multiple panels/, fn ->
      InstallationValidator.validate!(
        [
          panels: [:polychrome_panel_1, :polychrome_panel_prototype],
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
                 panels: [:polychrome_panel_prototype],
                 network_config: [mode: :individual]
               ],
               Hardware.registry()
             )
  end
end
