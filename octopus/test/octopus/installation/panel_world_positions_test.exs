defmodule Octopus.Installation.PanelWorldPositionsTest do
  use ExUnit.Case, async: true

  alias Octopus.Installation

  test "panel_world_positions_m returns empty list for linear installations" do
    assert Installation.panel_world_positions_m() == []
    assert Installation.panel_positions_m() == []
    assert Installation.ring_layout_m() == nil
  end

  test "panel_positions_m geometry: north at +Y, clockwise increase" do
    # Pure formula check for Nation2026-like numbers (independent of active install).
    positions =
      compute_positions(
        ring_radius_m: 10.0,
        panel_depth_m: 0.17,
        num_panels: 12,
        north_panel: 10,
        reference: :body_center
      )

    north = Enum.find(positions, &(&1.panel == 10))
    assert_in_delta north.x, 0.0, 1.0e-6
    assert_in_delta north.y, 10.085, 1.0e-3
    assert_in_delta north.theta_deg, 0.0, 1.0e-6

    # Panel 11 is one step clockwise from north (+X east of +Y north).
    next = Enum.find(positions, &(&1.panel == 11))
    assert next.x > 0.0
    assert next.y > 0.0
    assert_in_delta next.theta_deg, 30.0, 1.0e-6

    gravity =
      compute_positions(
        ring_radius_m: 10.0,
        panel_depth_m: 0.17,
        num_panels: 12,
        north_panel: 10,
        reference: :inner_face
      )

    gravity_north = Enum.find(gravity, &(&1.panel == 10))
    assert_in_delta gravity_north.x, 0.0, 1.0e-6
    assert_in_delta gravity_north.y, 10.0, 1.0e-3
  end

  test "sensor_mount_m uses +X / CCW convention" do
    {x, y} = Installation.sensor_mount_m(0.0, 100.0)
    assert_in_delta x, 1.0, 1.0e-6
    assert_in_delta y, 0.0, 1.0e-6

    {x90, y90} = Installation.sensor_mount_m(90.0, 200.0)
    assert_in_delta x90, 0.0, 1.0e-6
    assert_in_delta y90, 2.0, 1.0e-6
  end

  # Mirrors Installation.panel_positions_m/1 so circular installs can be tested
  # even when the test env loads a linear installation.
  defp compute_positions(opts) do
    ring_radius_m = Keyword.fetch!(opts, :ring_radius_m)
    panel_depth_m = Keyword.fetch!(opts, :panel_depth_m)
    num_panels = Keyword.fetch!(opts, :num_panels)
    north_panel = Keyword.fetch!(opts, :north_panel)
    reference = Keyword.get(opts, :reference, :body_center)

    radius_m =
      case reference do
        :inner_face -> ring_radius_m
        :body_center -> ring_radius_m + panel_depth_m / 2.0
      end

    step_deg = 360.0 / num_panels

    for n <- 1..num_panels do
      offset = Integer.mod(n - north_panel, num_panels)
      theta_deg = offset * step_deg
      theta_rad = theta_deg * :math.pi() / 180.0

      %{
        panel: n,
        x: radius_m * :math.sin(theta_rad),
        y: radius_m * :math.cos(theta_rad),
        theta_deg: theta_deg,
        theta_rad: theta_rad,
        offset: offset
      }
    end
  end
end
