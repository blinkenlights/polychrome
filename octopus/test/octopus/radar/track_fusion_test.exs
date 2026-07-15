defmodule Octopus.Radar.TrackFusionTest do
  use ExUnit.Case, async: false

  alias Octopus.Radar
  alias Octopus.Radar.TrackFusion

  setup do
    start_supervised!(TrackFusion)
    :ok
  end

  test "defaults to enabled with a 1 m radius" do
    assert TrackFusion.enabled?() == true
    assert TrackFusion.radius_m() == 1.0
  end

  test "set_enabled/1 and toggle_enabled/0" do
    TrackFusion.set_enabled(false)
    assert TrackFusion.enabled?() == false

    assert TrackFusion.toggle_enabled() == true
    assert TrackFusion.enabled?() == true
  end

  test "set_radius_m/1 clamps to the valid range" do
    TrackFusion.set_radius_m(0.02)
    assert TrackFusion.radius_m() == 0.1

    TrackFusion.set_radius_m(50.0)
    assert TrackFusion.radius_m() == 5.0

    TrackFusion.set_radius_m(1.5)
    assert TrackFusion.radius_m() == 1.5
  end

  test "Radar.fuse_people/1 merges duplicates while enabled" do
    Radar.set_track_fusion_enabled(true)
    Radar.set_track_fusion_radius_m(1.0)

    people = [
      %{id: 100_006, x: 0.0, y: 4.68, vx: 0.0, vy: 0.0},
      %{id: 200_006, x: 0.05, y: 4.70, vx: 0.0, vy: 0.0}
    ]

    assert [%{id: 100_006}] = Radar.fuse_people(people)
  end

  test "Radar.fuse_people/1 leaves tracks untouched while disabled" do
    Radar.set_track_fusion_enabled(false)

    people = [
      %{id: 100_006, x: 0.0, y: 4.68, vx: 0.0, vy: 0.0},
      %{id: 200_006, x: 0.05, y: 4.70, vx: 0.0, vy: 0.0}
    ]

    result = Radar.fuse_people(people)

    assert length(result) == 2
    assert Enum.map(result, & &1.id) |> Enum.sort() == [100_006, 200_006]
  end

  test "Radar.fuse_groups/1 exposes merge provenance" do
    Radar.set_track_fusion_enabled(true)
    Radar.set_track_fusion_radius_m(1.0)

    people = [
      %{id: 100_006, x: 0.0, y: 4.68, vx: 0.0, vy: 0.0},
      %{id: 200_006, x: 0.05, y: 4.70, vx: 0.0, vy: 0.0}
    ]

    assert [%{merged?: true, sources: sources}] = Radar.fuse_groups(people)
    assert length(sources) == 2
  end
end
