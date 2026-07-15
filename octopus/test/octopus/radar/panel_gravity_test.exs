defmodule Octopus.Radar.PanelGravityTest do
  use ExUnit.Case, async: false

  alias Octopus.Radar
  alias Octopus.Radar.{Frame, PanelGravity, Track}
  alias Octopus.Radar.PanelGravity.Settings

  setup do
    original = Application.get_env(:octopus, :installation)
    Application.put_env(:octopus, :installation, Octopus.Installation.Nation2026)

    on_exit(fn ->
      Application.put_env(:octopus, :installation, original)
    end)

    start_supervised!(Settings)
    start_supervised!(PanelGravity)
    :ok
  end

  test "panel_factors_gravity returns 1-based installation panel keys" do
    num_panels = Octopus.Installation.num_panels()
    gravity = Radar.panel_factors_gravity()

    assert map_size(gravity) == num_panels
    assert Map.has_key?(gravity, 1)
    assert Map.has_key?(gravity, num_panels)
    refute Map.has_key?(gravity, 0)
  end

  test "radar frame raises gravity for nearby panels" do
    north_panel = Octopus.Installation.north_panel()

    frame = %Frame{
      frame_number: 1,
      tracks: [%Track{id: 7, x: 0.0, y: 9.5, z: 0.0, vx: 0.0, vy: 0.0, vz: 0.0}],
      received_at: nil
    }

    send(PanelGravity, {:radar_frame, 1, frame})
    Process.sleep(300)

    snapshot = Radar.panel_gravity()
    raw_peak = snapshot.raw |> Map.values() |> Enum.max()
    assert raw_peak > 0.5

    gravity = snapshot.gravity
    {peak_panel, peak_value} = Enum.max_by(gravity, fn {_panel, value} -> value end)

    assert peak_panel == north_panel
    assert peak_value > 0.05

    # Peak panel dominates; distant panels stay clearly below it.
    Enum.each(gravity, fn {panel, value} ->
      if panel != north_panel do
        assert value < peak_value * 0.85
      end
    end)
  end

  test "gravity releases gradually after tracks go stale instead of snapping to zero" do
    frame = %Frame{
      frame_number: 1,
      tracks: [%Track{id: 9, x: 0.0, y: 10.0, z: 0.0, vx: 0.0, vy: 0.0, vz: 0.0}],
      received_at: nil
    }

    send(PanelGravity, {:radar_frame, 1, frame})
    Process.sleep(300)

    peak = Radar.panel_gravity().gravity |> Map.values() |> Enum.max()
    assert peak > 0.0

    :ok = Settings.update(track_stale_ms: 1)
    Process.sleep(5)
    PanelGravity.tick()
    Process.sleep(60)

    # The person is gone, so raw/target (instantaneous truth) clear immediately...
    %{raw: raw, target: target, gravity: gravity} = Radar.panel_gravity()
    assert Enum.all?(raw, fn {_panel, value} -> value == 0.0 end)
    assert Enum.all?(target, fn {_panel, value} -> value == 0.0 end)

    # ...but the displayed gravity (release envelope) is still fading out, not
    # already at zero — a real disappearance shouldn't snap to black.
    gravity_after = gravity |> Map.values() |> Enum.max()
    assert gravity_after > 0.0
    assert gravity_after < peak
  end

  test "target peaks follow person clockwise around the ring" do
    north = Octopus.Installation.north_panel()
    num_panels = Octopus.Installation.num_panels()
    positions = Octopus.Installation.panel_world_gravity_positions_m()

    cw1 = rem(north, num_panels) + 1
    cw2 = rem(cw1, num_panels) + 1
    p1 = Enum.find(positions, &(&1.panel == cw1))
    p2 = Enum.find(positions, &(&1.panel == cw2))

    send(PanelGravity, {:radar_frame, 1,
      %Frame{
        frame_number: 1,
        tracks: [%Track{id: 1, x: p1.x * 0.9, y: p1.y * 0.9, z: 0.0, vx: 0.0, vy: 0.0, vz: 0.0}],
        received_at: nil
      }})

    Process.sleep(60)
    {peak1, _} = Enum.max_by(Radar.panel_gravity().target, fn {_p, v} -> v end)
    assert peak1 == cw1

    send(PanelGravity, {:radar_frame, 1,
      %Frame{
        frame_number: 2,
        tracks: [%Track{id: 1, x: p2.x * 0.9, y: p2.y * 0.9, z: 0.0, vx: 0.0, vy: 0.0, vz: 0.0}],
        received_at: nil
      }})

    Process.sleep(60)
    {peak2, _} = Enum.max_by(Radar.panel_gravity().target, fn {_p, v} -> v end)
    assert peak2 == cw2
  end
end
