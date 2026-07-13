defmodule Octopus.Radar.ClutterFilterTest do
  use ExUnit.Case, async: false

  alias Octopus.Radar.{ClutterFilter, Frame, Track, ViewSettings}

  @device_id 1

  setup do
    Application.put_env(:octopus, ClutterFilter, stationary_filter_ms: 100)
    start_supervised!(ViewSettings)
    start_supervised!(ClutterFilter)
    ClutterFilter.reset()
    ViewSettings.set_clutter_filter(true)
    :ok
  end

  defp track(id, x, y, z \\ 1.7) do
    %Track{id: id, reserved: 0, x: x, y: y, z: z, vx: 0.0, vy: 0.0, vz: 0.0}
  end

  defp frame(tracks) do
    %Frame{frame_number: 1, tracks: tracks, received_at: System.monotonic_time(:millisecond)}
  end

  test "passes new tracks through immediately" do
    filtered = ClutterFilter.filter_frame(@device_id, frame([track(1, 0.0, 0.0)]))

    assert length(filtered.tracks) == 1
    assert hd(filtered.tracks).id == 1
  end

  test "drops tracks that never move beyond the jitter threshold" do
    frame = frame([track(1, 0.0, 0.0)])

    assert length(ClutterFilter.filter_frame(@device_id, frame).tracks) == 1
    Process.sleep(120)
    assert ClutterFilter.filter_frame(@device_id, frame).tracks == []
  end

  test "ignores jitter below the movement threshold" do
    frame = frame([track(1, 0.0, 0.0)])

    ClutterFilter.filter_frame(@device_id, frame)
    Process.sleep(120)

    jittered = ClutterFilter.filter_frame(@device_id, frame([track(1, 0.05, 0.05)]))

    assert jittered.tracks == []
  end

  test "drops tracks that moved once and then stand still long enough" do
    assert length(ClutterFilter.filter_frame(@device_id, frame([track(1, 0.0, 0.0)])).tracks) == 1
    assert length(ClutterFilter.filter_frame(@device_id, frame([track(1, 0.5, 0.0)])).tracks) == 1

    Process.sleep(120)

    standing =
      ClutterFilter.filter_frame(@device_id, frame([track(1, 0.5, 0.0)]))

    assert standing.tracks == []
  end

  test "keeps tracks that keep moving beyond the jitter threshold" do
    assert length(ClutterFilter.filter_frame(@device_id, frame([track(1, 0.0, 0.0)])).tracks) == 1

    Process.sleep(120)

    moved = ClutterFilter.filter_frame(@device_id, frame([track(1, 0.5, 0.0)]))

    assert length(moved.tracks) == 1
    assert hd(moved.tracks).x == 0.5
  end

  test "does not filter when clutter filter is disabled" do
    frame = frame([track(1, 0.0, 0.0)])

    assert length(ClutterFilter.filter_frame(@device_id, frame).tracks) == 1
    Process.sleep(120)
    ViewSettings.set_clutter_filter(false)

    assert length(ClutterFilter.filter_frame(@device_id, frame).tracks) == 1
  end

  test "reset clears track history" do
    frame = frame([track(1, 0.0, 0.0)])

    ClutterFilter.filter_frame(@device_id, frame)
    Process.sleep(120)
    assert ClutterFilter.filter_frame(@device_id, frame).tracks == []

    ClutterFilter.reset()
    assert length(ClutterFilter.filter_frame(@device_id, frame).tracks) == 1
  end
end
