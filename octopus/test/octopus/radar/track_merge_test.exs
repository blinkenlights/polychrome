defmodule Octopus.Radar.TrackMergeTest do
  use ExUnit.Case, async: true

  alias Octopus.Radar.TrackMerge

  test "merges tracks within radius into one centroid" do
    people = [
      %{id: 100_006, x: 0.09, y: 4.68, vx: 0.26, vy: 0.0},
      %{id: 200_006, x: 0.10, y: 4.67, vx: 0.24, vy: 0.01},
      %{id: 300_006, x: 0.08, y: 4.69, vx: 0.25, vy: -0.01}
    ]

    [merged] = TrackMerge.merge(people, 0.75)

    assert merged.id == 100_006
    assert_in_delta merged.x, 0.09, 0.02
    assert_in_delta merged.y, 4.68, 0.02
    assert_in_delta merged.vx, 0.25, 0.02
  end

  test "keeps distant tracks separate" do
    people = [
      %{id: 1, x: 0.0, y: 4.7, vx: 0.0, vy: 0.0},
      %{id: 2, x: -0.5, y: -7.0, vx: 0.2, vy: 0.0}
    ]

    assert length(TrackMerge.merge(people, 0.75)) == 2
  end

  test "does not merge same-bearing people at different radii (same device)" do
    # ~0.6 m apart on the same spoke — within old merge radius but distinct tracks.
    people = [
      %{id: 100_001, x: -3.46, y: -2.0, vx: 0.0, vy: 0.0},
      %{id: 100_002, x: -4.04, y: -2.33, vx: 0.0, vy: 0.0}
    ]

    assert length(TrackMerge.merge(people, 0.75)) == 2
  end

  test "does not merge same-bearing people even across devices" do
    people = [
      %{id: 100_001, x: -3.46, y: -2.0, vx: 0.0, vy: 0.0},
      %{id: 200_001, x: -4.04, y: -2.33, vx: 0.0, vy: 0.0}
    ]

    assert length(TrackMerge.merge(people, 0.75)) == 2
  end

  test "merges only cross-sensor duplicates at the same spot" do
    people = [
      %{id: 100_006, x: 0.09, y: 4.68, vx: 0.26, vy: 0.0},
      %{id: 100_007, x: 0.11, y: 4.70, vx: 0.0, vy: 0.0},
      %{id: 200_006, x: 0.10, y: 4.67, vx: 0.24, vy: 0.01}
    ]

    # Sensor 1 has two nearby tracks (different people) + sensor 2 duplicate of track 6.
    assert length(TrackMerge.merge(people, 0.75)) == 3
  end

  test "empty list stays empty" do
    assert TrackMerge.merge([]) == []
  end
end
