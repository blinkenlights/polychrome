defmodule Octopus.Recording.RadarRecorderTest do
  use ExUnit.Case, async: false

  alias Octopus.Radar
  alias Octopus.Radar.{Frame, Track}
  alias Octopus.Recording.{RadarFormat, RadarRecorder}

  setup do
    unless Process.whereis(Octopus.PubSub) do
      start_supervised!({Phoenix.PubSub, name: Octopus.PubSub})
    end

    unless Process.whereis(RadarRecorder) do
      start_supervised!(RadarRecorder)
    end

    _ = RadarRecorder.stop_recording()
    on_exit(fn -> _ = RadarRecorder.stop_recording() end)

    :ok
  end

  test "records radar frames as JSONL" do
    dir = Path.join(System.tmp_dir!(), "octorec-radar-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf(dir) end)

    assert {:ok, "file:" <> path} = RadarRecorder.start_recording(dir: dir)

    now = System.monotonic_time(:millisecond)

    frame1 = %Frame{
      frame_number: 1,
      received_at: now,
      tracks: [%Track{id: 7, reserved: 0, x: 1.0, y: 2.0, z: 0.5, vx: 0.1, vy: 0.2, vz: 0.0}]
    }

    frame2 = %Frame{frame_number: 2, received_at: now + 5, tracks: []}

    broadcast(1, frame1)
    broadcast(2, frame2)

    assert :ok = RadarRecorder.stop_recording()

    assert {:ok, meta, frames} = RadarFormat.parse(File.read!(path))
    assert meta["v"] == 1

    assert Enum.any?(frames, fn f ->
             f.dev == 1 and f.n == 1 and match?([%{id: 7}], f.tracks)
           end)

    assert Enum.any?(frames, fn f -> f.dev == 2 and f.n == 2 and f.tracks == [] end)
  end

  test "status reflects active/idle state" do
    dir = Path.join(System.tmp_dir!(), "octorec-radar-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf(dir) end)

    assert %{active: false} = RadarRecorder.status()
    assert {:ok, _} = RadarRecorder.start_recording(dir: dir)
    assert %{active: true} = RadarRecorder.status()
    assert :ok = RadarRecorder.stop_recording()
    assert %{active: false} = RadarRecorder.status()
  end

  defp broadcast(device_id, frame) do
    Phoenix.PubSub.broadcast(Octopus.PubSub, Radar.topic(), {:radar_frame, device_id, frame})
  end
end
