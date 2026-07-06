defmodule Octopus.Radar.PanelMappingTest do
  use ExUnit.Case, async: true

  alias Octopus.Radar.PanelMapping

  @num_panels 12
  @panel_width 8

  describe "sim_panel_3d/2 and frame mapping" do
    test "+Y (angle 0) → 3D panel 0 → canvas panel 11 (installation panel 12)" do
      track = %{x: 0.0, y: 9.0}
      assert PanelMapping.sim_panel_3d(track, @num_panels) == 0
      assert PanelMapping.frame_panel_of_3d(0, @num_panels) == 11

      {frame, _x} = PanelMapping.track_to_panel_pos(track, @num_panels, @panel_width)
      assert frame == 11
    end

    test "panel 1 position (~11/12 turn) → canvas panel 0" do
      # 3D panel 11 sits at 11/12 · 2π; textureIdx 0 = installation panel 1
      angle = 11.0 / @num_panels * 2.0 * :math.pi()
      track = %{x: 9.0 * :math.sin(angle), y: 9.0 * :math.cos(angle)}

      assert PanelMapping.sim_panel_3d(track, @num_panels) == 11

      {frame, _x} = PanelMapping.track_to_panel_pos(track, @num_panels, @panel_width)
      assert frame == 0
    end

    test "round beats trunc near sector boundary (no +1 panel slip)" do
      # Between 3D panel 10 and 11 — closer to 11
      norm = (10.0 + 0.6) / @num_panels
      angle = norm * 2.0 * :math.pi()
      track = %{x: 9.0 * :math.sin(angle), y: 9.0 * :math.cos(angle)}

      assert PanelMapping.sim_panel_3d(track, @num_panels) == 11
    end
  end

  describe "in_ring?/3" do
    test "respects inner and outer bounds" do
      assert PanelMapping.in_ring?(%{x: 0.0, y: 8.0}, 4.0, 10.0)
      assert PanelMapping.in_ring?(%{x: 0.0, y: 5.0}, 4.0, 10.0)
      refute PanelMapping.in_ring?(%{x: 0.0, y: 2.0}, 4.0, 10.0)
      refute PanelMapping.in_ring?(%{x: 0.0, y: 11.0}, 4.0, 10.0)
    end
  end
end
