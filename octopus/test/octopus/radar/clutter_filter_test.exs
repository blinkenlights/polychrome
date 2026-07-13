defmodule Octopus.Radar.ClutterFilterTest do
  use ExUnit.Case, async: false

  alias Octopus.Radar.{ClutterFilter, Frame, Track, ViewSettings}

  @device_id 1

  setup do
    Application.put_env(:octopus, ClutterFilter, qualification_ms: 100)
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

  test "holds back unqualified tracks" do
    assert ClutterFilter.filter_frame(@device_id, frame([track(1, 0.0, 0.0)])).tracks == []
  end

  test "never qualifies stationary clutter" do
    frame = frame([track(1, 0.0, 0.0)])

    ClutterFilter.filter_frame(@device_id, frame)
    Process.sleep(120)
    assert ClutterFilter.filter_frame(@device_id, frame).tracks == []

    jittered = ClutterFilter.filter_frame(@device_id, frame([track(1, 0.05, 0.05)]))
    assert jittered.tracks == []
  end

  test "qualifies tracks after enough accumulated movement time" do
    assert ClutterFilter.filter_frame(@device_id, frame([track(1, 0.0, 0.0)])).tracks == []

    Process.sleep(60)
    assert ClutterFilter.filter_frame(@device_id, frame([track(1, 0.5, 0.0)])).tracks == []

    Process.sleep(60)

    qualified =
      ClutterFilter.filter_frame(@device_id, frame([track(1, 1.0, 0.0)]))

    assert length(qualified.tracks) == 1
    assert hd(qualified.tracks).x == 1.0
  end

  test "keeps qualified tracks visible when they stop moving" do
    assert ClutterFilter.filter_frame(@device_id, frame([track(1, 0.0, 0.0)])).tracks == []

    Process.sleep(60)
    ClutterFilter.filter_frame(@device_id, frame([track(1, 0.5, 0.0)]))
    Process.sleep(60)

    assert length(ClutterFilter.filter_frame(@device_id, frame([track(1, 1.0, 0.0)])).tracks) == 1

    Process.sleep(200)

    standing =
      ClutterFilter.filter_frame(@device_id, frame([track(1, 1.0, 0.0)]))

    assert length(standing.tracks) == 1
    assert hd(standing.tracks).x == 1.0
  end

  test "does not filter when clutter filter is disabled" do
    ViewSettings.set_clutter_filter(false)

    assert length(ClutterFilter.filter_frame(@device_id, frame([track(1, 0.0, 0.0)])).tracks) == 1
  end

  test "reset clears qualification progress" do
    Process.sleep(60)
    ClutterFilter.filter_frame(@device_id, frame([track(1, 0.5, 0.0)]))

    ClutterFilter.reset()

    assert ClutterFilter.filter_frame(@device_id, frame([track(1, 0.5, 0.0)])).tracks == []
  end
end
