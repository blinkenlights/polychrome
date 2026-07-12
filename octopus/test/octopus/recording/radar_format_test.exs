defmodule Octopus.Recording.RadarFormatTest do
  use ExUnit.Case, async: true

  alias Octopus.Recording.RadarFormat
  alias Octopus.Radar.Track

  test "round-trips metadata and frames through parse/1" do
    track = %Track{id: 7, reserved: 0, x: 1.5, y: -2.25, z: 0.5, vx: 0.125, vy: -0.5, vz: 0.0}

    binary =
      RadarFormat.meta_line(1_700_000_000_000, 8.0) <>
        RadarFormat.frame_line(123, 2, 42, [track])

    assert {:ok, meta, frames} = RadarFormat.parse(binary)

    assert meta["v"] == 1
    assert meta["started_at_ms"] == 1_700_000_000_000
    assert meta["world_radius_m"] == 8.0

    assert [frame] = frames
    assert frame.t == 123
    assert frame.dev == 2
    assert frame.n == 42

    assert [t] = frame.tracks
    assert t.id == 7
    assert t.x == 1.5
    assert t.y == -2.25
    assert t.z == 0.5
    assert t.vx == 0.125
  end

  test "handles frames with no tracks" do
    binary =
      RadarFormat.meta_line(0, 8.0) <>
        RadarFormat.frame_line(10, 1, 1, [])

    assert {:ok, _meta, [frame]} = RadarFormat.parse(binary)
    assert frame.tracks == []
  end

  test "reports empty recordings" do
    assert {:error, :empty_recording} = RadarFormat.parse("")
  end
end
