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
    for n <- 1..12 do
      theta = (n - 1) / 12 * 2.0 * :math.pi()
      %{panel: n, x: center_r * :math.sin(theta), y: center_r * :math.cos(theta)}
    end
  end

  test "contribution falls off with distance" do
    s = settings(reach: 50, softening_m: 0.25, mass: 1.0)
    panel = %{panel: 1, x: 0.0, y: 10.0}

    near = Core.contribution(person(x: 0.0, y: 10.1), panel, s)
    far = Core.contribution(person(x: 0.0, y: 5.0), panel, s)

    assert near > far
    assert near > 0.0
    assert far > 0.0
  end

  test "center object yields identical gravity on every ring panel" do
    s = settings(reach: 100, contrast: 3.0, sensitivity: 1.0)
    panels = ring_panels(10.0)
    raw = Core.raw_gravity([person(x: 0.0, y: 0.0)], panels, s)

    values = Map.values(raw)
    assert_in_delta Enum.max(values), Enum.min(values), 1.0e-9
  end

  test "center object at reach 100 is about 50% on every panel" do
    s = settings(reach: 100, contrast: 3.0, sensitivity: 1.0, softening_m: 0.25)
    panels = ring_panels(10.0)
    raw = Core.raw_gravity([person(x: 0.0, y: 0.0)], panels, s)
    targets = Core.targets(raw, 1.0, s)

    Enum.each(targets, fn {_panel, level} ->
      assert_in_delta level, 0.5, 0.05
    end)
  end

  test "higher reach raises absolute gravity at a fixed distance" do
    panel = %{panel: 1, x: 0.0, y: 10.0}
    at_center = person(x: 0.0, y: 0.0)

    low = Core.contribution(at_center, panel, settings(reach: 1))
    mid = Core.contribution(at_center, panel, settings(reach: 50))
    high = Core.contribution(at_center, panel, settings(reach: 100))

    assert mid > low
    assert high > mid
  end

  test "raw_gravity sums every object onto every panel" do
    s = settings(reach: 100)
    panels = ring_panels(10.0)
    one = Core.raw_gravity([person(id: 1, x: 0.0, y: 0.0)], panels, s)

    two =
      Core.raw_gravity(
        [person(id: 1, x: 0.0, y: 0.0), person(id: 2, x: 0.0, y: 0.0)],
        panels,
        s
      )

    assert_in_delta two[1], one[1] * 2.0, 1.0e-9
  end

  test "raw_gravity peaks on the nearest panel" do
    s = settings(reach: 20, softening_m: 0.25)
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

  test "targets map absolute values without cross-panel min-max" do
    s = settings(sensitivity: 1.0, contrast: 3.0)
    # Equal mid values stay equal mid — not remapped to 0/1.
    targets = Core.targets(%{1 => 0.5, 2 => 0.5, 3 => 0.5}, 1.0, s)

    assert_in_delta targets[1], 0.5, 1.0e-6
    assert_in_delta targets[2], 0.5, 1.0e-6
    assert_in_delta targets[3], 0.5, 1.0e-6
  end

  test "targets are zero when all panels are zero" do
    targets = Core.targets(%{1 => 0.0, 2 => 0.0}, 1.0, settings([]))

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
