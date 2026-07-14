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

    test "installation_panel_of_frame respects north_panel" do
      # +Y (north) → 3D panel 0; with north_panel 10 that is physical panel 10.
      assert PanelMapping.installation_panel_of_frame(11, @num_panels, 10) == 10

      # East (+X) → 3D panel 3; with north_panel 10 that is physical panel 1.
      assert PanelMapping.installation_panel_of_frame(8, @num_panels, 10) == 1

      # Default north_panel 1: +Y → physical panel 1, 11/12 turn → panel 12.
      assert PanelMapping.installation_panel_of_frame(11, @num_panels, 1) == 1
      assert PanelMapping.installation_panel_of_frame(0, @num_panels, 1) == 12
    end

    test "round beats trunc near sector boundary (no +1 panel slip)" do
      # Between 3D panel 10 and 11 — closer to 11
      norm = (10.0 + 0.6) / @num_panels
      angle = norm * 2.0 * :math.pi()
      track = %{x: 9.0 * :math.sin(angle), y: 9.0 * :math.cos(angle)}

      assert PanelMapping.sim_panel_3d(track, @num_panels) == 11
    end
  end

  describe "track_to_canvas_xy/3" do
    test "+Y on ring → top row, canvas panel 11" do
      track = %{x: 0.0, y: 9.0}
      height = 32

      {col, row} = PanelMapping.track_to_canvas_xy(track, @num_panels, height, @panel_width)

      assert col >= 11 * @panel_width
      assert col < 12 * @panel_width
      assert row < height * 0.3
    end

    test "centre → bottom row" do
      track = %{x: 0.0, y: 0.0}
      height = 32

      {_col, row} = PanelMapping.track_to_canvas_xy(track, @num_panels, height, @panel_width)

      assert row == height - 1.0
    end

    test "column is float within panel bounds" do
      norm = 0.42
      angle = norm * 2.0 * :math.pi()
      track = %{x: 5.0 * :math.sin(angle), y: 5.0 * :math.cos(angle)}
      height = 32

      {col, _row} = PanelMapping.track_to_canvas_xy(track, @num_panels, height, @panel_width)

      frame = PanelMapping.frame_panel_of_3d(PanelMapping.sim_panel_3d(track, @num_panels), @num_panels)
      assert col >= frame * @panel_width
      assert col < (frame + 1) * @panel_width
      assert col != trunc(col) or col == frame * @panel_width
    end
  end

  describe "texture_index_for_frame/3" do
    test "north at +Y maps frame 11 → texture 9 (panel 10)" do
      assert PanelMapping.texture_index_for_frame(11, @num_panels, 10) == 9
    end

    test "frame_panel_for_installation inverts correctly" do
      assert PanelMapping.frame_panel_for_installation(10, @num_panels, 10) == 11
      assert PanelMapping.frame_panel_for_installation(12, @num_panels, 1) == 0
    end

    test "canvas_to_texture round-trips every frame panel" do
      mapping = PanelMapping.canvas_to_texture(@num_panels, 10)

      assert length(mapping) == @num_panels

      for f <- 0..(@num_panels - 1) do
        assert Enum.at(mapping, f) == PanelMapping.texture_index_for_frame(f, @num_panels, 10)
      end
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
