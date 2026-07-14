defmodule Octopus.Radar.PanelActivityTest do
  use ExUnit.Case, async: false

  alias Octopus.Radar
  alias Octopus.Radar.{Frame, PanelActivity, Track}
  alias Octopus.Radar.PanelActivity.Settings

  setup do
    start_supervised!(Octopus.Radar.PanelActivity.Settings)
    start_supervised!(PanelActivity)
    :ok
  end

  test "panel_factors returns 1-based installation panel keys" do
    num_panels = Octopus.Installation.num_panels()
    factors = Radar.panel_factors()

    assert map_size(factors) == num_panels
    assert Map.has_key?(factors, 1)
    assert Map.has_key?(factors, num_panels)
    refute Map.has_key?(factors, 0)
  end

  test "radar frame raises activity for the mapped panel" do
    frame = %Frame{
      frame_number: 1,
      tracks: [%Track{id: 7, x: 0.0, y: 10.0, z: 0.0, vx: 0.0, vy: 0.0, vz: 0.0}],
      received_at: nil
    }

    send(PanelActivity, {:radar_frame, 1, frame})
    _ = Radar.panel_activity()
    PanelActivity.tick()
    _ = Radar.panel_activity()

    snapshot = Radar.panel_activity()
    assert Enum.any?(snapshot.raw, fn {_panel, value} -> value > 0.0 end)
    assert Enum.any?(snapshot.factors, fn {_panel, value} -> value > 0.0 end)
  end

  test "activity fades down after tracks disappear" do
    frame = %Frame{
      frame_number: 1,
      tracks: [%Track{id: 9, x: 0.0, y: 10.0, z: 0.0, vx: 0.0, vy: 0.0, vz: 0.0}],
      received_at: nil
    }

    send(PanelActivity, {:radar_frame, 1, frame})
    _ = Radar.panel_activity()
    PanelActivity.tick()
    _ = Radar.panel_activity()

    peak = Radar.panel_factors() |> Map.values() |> Enum.max()

    assert peak > 0.0

    :ok = Settings.update(track_stale_ms: 1)
    Process.sleep(2)

    PanelActivity.tick()
    %{raw: raw} = Radar.panel_activity()
    assert Enum.all?(raw, fn {_panel, value} -> value == 0.0 end)

    early = Radar.panel_factors() |> Map.values() |> Enum.max()
    assert early > 0.0

    Enum.each(1..12, fn _ -> PanelActivity.tick() end)
    late = Radar.panel_factors() |> Map.values() |> Enum.max()

    assert late < early
    assert late >= 0.0
  end

  test "merges multi-sensor duplicates before activity calculation" do
    track = %Track{id: 6, x: 0.09, y: 4.68, z: 0.0, vx: 0.26, vy: 0.0, vz: 0.0}

    single_frame = %Frame{frame_number: 1, tracks: [track], received_at: nil}
    send(PanelActivity, {:radar_frame, 1, single_frame})
    PanelActivity.tick()
    single_peak = Radar.panel_activity().raw |> Map.values() |> Enum.max()

    for device_id <- 2..3 do
      send(PanelActivity, {:radar_frame, device_id, single_frame})
    end

    PanelActivity.tick()
    triple_peak = Radar.panel_activity().raw |> Map.values() |> Enum.max()

    assert single_peak > 0.0
    assert_in_delta single_peak, triple_peak, single_peak * 0.15
  end

  test "panel_activity snapshot exposes raw and ref" do
    %{factors: factors, raw: raw, ref: ref, at: at} = Radar.panel_activity()

    assert is_map(factors)
    assert is_map(raw)
    assert is_float(ref)
    assert is_integer(at)
  end
end
