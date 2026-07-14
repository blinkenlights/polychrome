defmodule Octopus.Radar.PanelActivity.SettingsTest do
  use ExUnit.Case, async: false

  alias Octopus.Radar.PanelActivity.Settings

  setup do
    start_supervised!(Settings)
    :ok
  end

  test "defaults include installation overrides when present" do
    settings = Settings.get()

    assert settings.sensitivity == 1.0
    assert settings.adaptive == true
    assert settings.release_tau == 5.0
    assert settings.tick_hz == 25
  end

  test "update/1 changes runtime settings" do
    assert :ok = Settings.update(sensitivity: 2.0, adaptive: false)
    settings = Settings.get()

    assert settings.sensitivity == 2.0
    assert settings.adaptive == false
  end
end
