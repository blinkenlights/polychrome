defmodule Octopus.Radar.ViewSettingsTest do
  use ExUnit.Case, async: false

  alias Octopus.Radar.ViewSettings

  setup do
    start_supervised!(ViewSettings)
    :ok
  end

  test "defaults match installation and UI presets" do
    settings = ViewSettings.get()

    assert settings.north_panel == Octopus.Installation.north_panel()
    assert settings.detection_list_mode == :by_sensor
    assert settings.coords_frame == :global
    assert settings.bounds_mode == :static
    assert settings.visuals == ViewSettings.default_visuals()
  end

  test "north_panel is clamped to the installation panel count" do
    max = Octopus.Installation.num_panels()
    assert :ok = ViewSettings.set_north_panel(999)
    assert ViewSettings.north_panel() == max
  end

  test "toggle_coords_frame flips between global and local" do
    assert ViewSettings.coords_frame() == :global
    assert ViewSettings.toggle_coords_frame() == :local
    assert ViewSettings.coords_frame() == :local
    assert ViewSettings.toggle_coords_frame() == :global
  end

  test "toggle_visual flips a known layer" do
    assert ViewSettings.visuals().arrows == false
    assert :ok = ViewSettings.toggle_visual(:arrows)
    assert ViewSettings.visuals().arrows == true
    assert :error = ViewSettings.toggle_visual(:unknown_layer)
  end
end
