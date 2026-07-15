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
    assert settings.reach == 50
    assert settings.contrast == 3.0
    assert settings.min_ref == 1.0e-4
    assert settings.tick_hz == 25
  end

  test "update/1 changes runtime settings" do
    :ok = Settings.update(reach: 80, softening_m: 0.25)
    settings = Settings.get()

    assert settings.reach == 80
    assert settings.softening_m == 0.25
  end

  test "update/1 clamps reach to 1..100" do
    :ok = Settings.update(reach: 0)
    assert Settings.get().reach == 1

    :ok = Settings.update(reach: 250)
    assert Settings.get().reach == 100
  end
end
