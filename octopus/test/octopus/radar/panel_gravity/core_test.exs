defmodule Octopus.Radar.PanelGravity.CoreTest do
  use ExUnit.Case, async: true

  alias Octopus.Radar.PanelGravity.{Core, Settings}

  defp settings(overrides) do
    struct(Settings, Keyword.merge(Map.to_list(Settings.defaults()), overrides))
  end

  defp person(opts) do
    %{
      id: Keyword.get(opts, :id, 1),
      x: Keyword.get(opts, :x, 0.0),
      y: Keyword.get(opts, :y, 0.0),
      vx: Keyword.get(opts, :vx, 0.0),
      vy: Keyword.get(opts, :vy, 0.0)
    }
  end

  defp ring_panels(center_r) do
    for n <- 1..4 do
      theta = (n - 1) / 4 * 2.0 * :math.pi()
      %{panel: n, x: center_r * :math.sin(theta), y: center_r * :math.cos(theta)}
    end
  end

  test "contribution falls off with distance" do
    s = settings(exponent: 2.0, softening_m: 0.5, mass: 1.0)
    panel = %{panel: 1, x: 0.0, y: 10.0}

    near = Core.contribution(person(x: 0.0, y: 10.1), panel, s)
    far = Core.contribution(person(x: 0.0, y: 5.0), panel, s)

    assert near > far
    assert near > 0.0
    assert far > 0.0
  end

  test "raw_gravity peaks on the nearest panel" do
    s = settings(exponent: 2.0, softening_m: 0.5)
    panels = ring_panels(10.0)
    north_panel = Enum.max_by(panels, & &1.y)
    person_at_north = person(x: north_panel.x, y: north_panel.y - 0.5)

    raw = Core.raw_gravity([person_at_north], panels, s)

    north_value = Map.fetch!(raw, north_panel.panel)

    Enum.each(raw, fn {panel, value} ->
      if panel != north_panel.panel do
        assert north_value > value
      end
    end)
  end

  test "targets peaks on the brightest panel and sharpens neighbors" do
    raw = %{1 => 0.01, 2 => 0.1, 3 => 0.08}
    targets = Core.targets(raw, 1.0, settings(sensitivity: 1.0, contrast: 3.0, min_ref: 1.0e-4))

    assert targets[2] == 1.0
    assert targets[3] < 0.6
    assert targets[1] < 0.1
  end

  test "targets are zero when all panels are equal" do
    raw = %{1 => 0.01, 2 => 0.01, 3 => 0.01}
    targets = Core.targets(raw, 1.0, settings(sensitivity: 1.0))

    assert Enum.all?(targets, fn {_panel, value} -> value == 0.0 end)
  end

  test "smooth_asymmetric attacks faster than it releases" do
    s = settings(attack_tau: 0.2, release_tau: 5.0)
    dt = 0.04

    up = Core.smooth_asymmetric(%{1 => 0.0}, %{1 => 1.0}, dt, s)
    down = Core.smooth_asymmetric(%{1 => 1.0}, %{1 => 0.0}, dt, s)

    assert up[1] > 1.0 - down[1]
  end
end
