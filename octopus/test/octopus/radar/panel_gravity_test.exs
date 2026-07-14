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
    Process.sleep(100)
    PanelGravity.tick()

    snapshot = Radar.panel_gravity()
    raw_peak = snapshot.raw |> Map.values() |> Enum.max()
    assert raw_peak > 0.5

    gravity = snapshot.gravity
    {peak_panel, peak_value} = Enum.max_by(gravity, fn {_panel, value} -> value end)

    assert peak_panel == north_panel
    assert peak_value > 0.3

    Enum.each(gravity, fn {panel, value} ->
      if panel != north_panel do
        assert value < peak_value * 0.5
      end
    end)
  end

  test "gravity fades down after tracks disappear" do
    frame = %Frame{
      frame_number: 1,
      tracks: [%Track{id: 9, x: 0.0, y: 10.0, z: 0.0, vx: 0.0, vy: 0.0, vz: 0.0}],
      received_at: nil
    }

    send(PanelGravity, {:radar_frame, 1, frame})
    PanelGravity.tick()

    peak = Radar.panel_factors_gravity() |> Map.values() |> Enum.max()
    assert peak > 0.0

    :ok = Settings.update(track_stale_ms: 1)
    Process.sleep(2)

    PanelGravity.tick()
    %{raw: raw} = Radar.panel_gravity()
    assert Enum.all?(raw, fn {_panel, value} -> value == 0.0 end)

    early = Radar.panel_factors_gravity() |> Map.values() |> Enum.max()
    assert early > 0.0

    Enum.each(1..12, fn _ -> PanelGravity.tick() end)
    late = Radar.panel_factors_gravity() |> Map.values() |> Enum.max()

    assert late < early
    assert late >= 0.0
  end
end
