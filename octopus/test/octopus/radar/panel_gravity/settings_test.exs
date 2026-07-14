defmodule Octopus.Radar.PanelGravity.SettingsTest do
  use ExUnit.Case, async: false

  alias Octopus.Radar.PanelGravity.Settings

  setup do
    start_supervised!(Settings)
    :ok
  end

  test "defaults include gravity tuning keys" do
    settings = Settings.get()

    assert settings.exponent == 3.0
    assert settings.softening_m == 0.25
    assert settings.contrast == 3.0
    assert settings.min_ref == 1.0e-4
    assert settings.tick_hz == 25
  end

  test "update/1 changes runtime settings" do
    :ok = Settings.update(exponent: 3.0, softening_m: 0.25)
    settings = Settings.get()

    assert settings.exponent == 3.0
    assert settings.softening_m == 0.25
  end
end
