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

  defp track(id, x, y, z \\ 1.7, opts \\ []) do
    {vx, vy, vz} = Keyword.get(opts, :velocity, {0.0, 0.0, 0.0})

    %Track{
      id: id,
      reserved: 0,
      x: x,
      y: y,
      z: z,
      vx: vx,
      vy: vy,
      vz: vz
    }
  end

  defp frame(tracks, opts \\ []) do
    ts = Keyword.get(opts, :received_at, System.monotonic_time(:millisecond))

    %Frame{frame_number: 1, tracks: tracks, received_at: ts}
  end

  test "holds back unqualified tracks" do
    assert ClutterFilter.filter_frame(@device_id, frame([track(1, 0.0, 0.0)])).tracks == []
  end

  test "never qualifies stationary clutter" do
    frame = frame([track(1, 0.0, 0.0)])

    ClutterFilter.filter_frame(@device_id, frame)
    Process.sleep(120)
    assert ClutterFilter.filter_frame(@device_id, frame).tracks == []

    jittered = ClutterFilter.filter_frame(@device_id, frame([track(1, 0.02, 0.02)]))
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

  test "qualifies tracks with sustained velocity even when frame steps are small" do
    moving = track(0, 2.2354, -4.7671, 3.841, velocity: {-0.3417, -0.0585, -0.2525})

    assert ClutterFilter.filter_frame(5, frame([moving])).tracks == []

    Process.sleep(60)
    assert ClutterFilter.filter_frame(5, frame([%{moving | x: 2.24, y: -4.77}])).tracks == []

    Process.sleep(60)

    qualified =
      ClutterFilter.filter_frame(5, frame([%{moving | x: 2.25, y: -4.78}]))

    assert length(qualified.tracks) == 1
    assert hd(qualified.tracks).id == 0
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

  test "track_debug returns movement history and filter state" do
    moving = track(0, 2.0, -4.0, 3.8, velocity: {-0.34, -0.06, -0.25})

    ClutterFilter.filter_frame(5, frame([moving]))
    Process.sleep(60)
    ClutterFilter.filter_frame(5, frame([%{moving | x: 2.05, y: -4.05}]))
    Process.sleep(60)
    ClutterFilter.filter_frame(5, frame([%{moving | x: 2.1, y: -4.1}]))

    debug = ClutterFilter.track_debug(5, 0)

    assert debug["track"]["label"] == "E0"
    assert debug["filter"]["qualified"] == true
    assert length(debug["history"]) == 3
    assert hd(debug["history"])["moving"] == true
    assert is_float(hd(debug["history"])["speed_m_s"])
  end

  test "qualification persists when clutter filter is toggled off and on" do
    moving = track(1, 0.0, 0.0, 1.7, velocity: {0.5, 0.0, 0.0})
    t0 = System.monotonic_time(:millisecond)

    assert ClutterFilter.filter_frame(@device_id, frame([moving], received_at: t0)).tracks == []
    assert ClutterFilter.filter_frame(@device_id, frame([moving], received_at: t0 + 50)).tracks == []

    qualified =
      ClutterFilter.filter_frame(@device_id, frame([moving], received_at: t0 + 100))

    assert length(qualified.tracks) == 1

    ViewSettings.set_clutter_filter(false)
    assert length(ClutterFilter.filter_frame(@device_id, frame([moving], received_at: t0 + 120)).tracks) == 1

    ViewSettings.set_clutter_filter(true)

    assert length(ClutterFilter.filter_frame(@device_id, frame([moving], received_at: t0 + 140)).tracks) == 1
  end

  test "track_qualified? reflects registry qualification state" do
    moving = track(1, 0.0, 0.0, 1.7, velocity: {0.5, 0.0, 0.0})
    t0 = System.monotonic_time(:millisecond)

    assert ClutterFilter.track_qualified?(@device_id, 1) == false

    ClutterFilter.filter_frame(@device_id, frame([moving], received_at: t0))
    ClutterFilter.filter_frame(@device_id, frame([moving], received_at: t0 + 50))

    assert ClutterFilter.track_qualified?(@device_id, 1) == false

    ClutterFilter.filter_frame(@device_id, frame([moving], received_at: t0 + 100))

    assert ClutterFilter.track_qualified?(@device_id, 1) == true
  end

  test "track_debug returns nil for unknown tracks" do
    assert ClutterFilter.track_debug(9, 99) == nil
  end
end
