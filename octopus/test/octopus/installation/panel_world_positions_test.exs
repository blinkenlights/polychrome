defmodule Octopus.Installation.PanelWorldPositionsTest do
  use ExUnit.Case, async: true

  alias Octopus.Installation

  test "panel_world_positions_m returns empty list for linear installations" do
    assert Installation.panel_world_positions_m() == []
  end

  test "circular geometry matches ring layout formula" do
    positions =
      circular_positions(
        ring_radius_m: 10.0,
        panel_depth_m: 0.17,
        num_panels: 12,
        north_panel: 10
      )

    north = Enum.find(positions, &(&1.panel == 10))

    assert_in_delta north.x, 0.0, 1.0e-6
    assert_in_delta north.y, 10.085, 1.0e-3

    assert length(positions) == 12
    assert Enum.all?(positions, &match?(%{panel: _, x: _, y: _}, &1))

    gravity =
      circular_positions(
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

  defp circular_positions(opts) do
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
      theta_rad = offset * step_deg * :math.pi() / 180.0

      %{
        panel: n,
        x: radius_m * :math.sin(theta_rad),
        y: radius_m * :math.cos(theta_rad)
      }
    end
  end
end
