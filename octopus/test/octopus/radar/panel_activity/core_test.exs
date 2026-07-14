defmodule Octopus.Radar.PanelActivity.CoreTest do
  use ExUnit.Case, async: true

  alias Octopus.Radar.PanelActivity.{Core, Settings}

  defp settings(overrides \\ []) do
    struct(Settings, Keyword.merge(Map.to_list(Settings.defaults()), overrides))
  end

  defp person(opts) do
    %{
      id: Keyword.get(opts, :id, 1),
      x: Keyword.get(opts, :x, 0.0),
      y: Keyword.get(opts, :y, 10.0),
      vx: Keyword.get(opts, :vx, 0.0),
      vy: Keyword.get(opts, :vy, 0.0)
    }
  end

  test "raw_factors weights ring-edge people higher than centre" do
    centre = person(x: 0.0, y: 0.0)
    ring = person(x: 0.0, y: 10.0)
    s = settings()

    centre_raw =
      centre
      |> List.wrap()
      |> Core.raw_factors(12, 10.0, s)
      |> Map.values()
      |> Enum.sum()

    ring_raw =
      ring
      |> List.wrap()
      |> Core.raw_factors(12, 10.0, s)
      |> Map.values()
      |> Enum.sum()

    assert ring_raw > centre_raw
    assert centre_raw == 1.0
    assert ring_raw == 3.0
  end

  test "raw_factors doubles contribution for walking people" do
    standing = person(vx: 0.0, vy: 0.0)
    walking = person(vx: 0.0, vy: 0.5)
    s = settings()

    standing_sum =
      standing
      |> List.wrap()
      |> Core.raw_factors(12, 10.0, s)
      |> Map.values()
      |> Enum.sum()

    walking_sum =
      walking
      |> List.wrap()
      |> Core.raw_factors(12, 10.0, s)
      |> Map.values()
      |> Enum.sum()

    assert walking_sum == standing_sum * 2.0
  end

  test "targets soft-compresses against ref" do
    raw = %{0 => 4.0}
    targets = Core.targets(raw, 4.0, settings(sensitivity: 1.0))

    assert targets[0] == 0.5
  end

  test "smooth_asymmetric attacks faster than it releases" do
    s = settings(attack_tau: 0.2, release_tau: 5.0)
    dt = 0.04

    up = Core.smooth_asymmetric(%{1 => 0.0}, %{1 => 1.0}, dt, s)
    down = Core.smooth_asymmetric(%{1 => 1.0}, %{1 => 0.0}, dt, s)

    up_delta = up[1]
    down_delta = 1.0 - down[1]

    assert up_delta > down_delta
    assert up[1] > 0.15
    assert down[1] > 0.99
  end

  test "to_installation_panels maps frame index to physical panels (north_panel 1)" do
    mapped = Core.to_installation_panels(%{0 => 0.5, 11 => 0.2}, 12, 1)

    assert mapped[12] == 0.5
    assert mapped[1] == 0.2
    assert map_size(mapped) == 12
  end

  test "to_installation_panels honours north_panel offset" do
    mapped = Core.to_installation_panels(%{8 => 0.7, 11 => 0.3}, 12, 10)

    assert mapped[1] == 0.7
    assert mapped[10] == 0.3
  end
end
