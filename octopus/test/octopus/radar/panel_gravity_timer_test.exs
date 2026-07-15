defmodule Octopus.Radar.PanelGravityTimerTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Octopus.Radar.{Frame, PanelGravity, Track}
  alias Octopus.Radar.PanelGravity.Settings

  setup do
    original = Application.get_env(:octopus, :installation)
    Application.put_env(:octopus, :installation, Octopus.Installation.Nation2026)

    on_exit(fn ->
      Application.put_env(:octopus, :installation, original)
    end)

    start_supervised!(Settings)
    :ok
  end

  test "radar frame updates the snapshot and the fast attack catches up to target" do
    start_supervised!(PanelGravity)

    Process.sleep(30)
    snap0 = PanelGravity.snapshot()

    frame = %Frame{
      frame_number: 1,
      tracks: [%Track{id: 1, x: 0.0, y: 9.5, z: 0.0, vx: 0.0, vy: 0.0, vz: 0.0}],
      received_at: nil
    }

    send(PanelGravity, {:radar_frame, 1, frame})
    Process.sleep(30)
    snap_after_first_frame = PanelGravity.snapshot()

    assert snap_after_first_frame.at != 0
    assert snap_after_first_frame.at != snap0.at or
             Map.values(snap_after_first_frame.raw) != Map.values(snap0.raw)

    # Simulate the object staying in place with continuous radar frames (as a
    # real track would) so it never goes stale while we wait for the smoothed
    # gravity to catch up to the instantaneous target.
    for frame_number <- 2..16 do
      send(PanelGravity, {:radar_frame, frame_number, frame})
      Process.sleep(80)
    end

    snap1 = PanelGravity.snapshot()

    # Attack is quick but visible (attack_tau ≈ 200 ms) — after ~6 tau (1.2 s)
    # of continuous tracking the smoothed gravity has essentially caught up
    # to the instantaneous target, so a moving object never looks stuck.
    Enum.each(snap1.target, fn {panel, target_value} ->
      assert_in_delta Map.fetch!(snap1.gravity, panel), target_value, 0.02
    end)
  end

  test "debug logs fire even when monotonic time is negative relative to zero" do
    previous = Logger.level()
    Logger.configure(level: :debug)

    log =
      capture_log(fn ->
        start_supervised!(PanelGravity)
        Process.sleep(50)
      end)

    Logger.configure(level: previous)
    assert log =~ "[PanelGravity]"
  end
end
