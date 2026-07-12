defmodule Octopus.Recording.SessionTest do
  use ExUnit.Case, async: false

  alias Octopus.Recording

  setup do
    unless Process.whereis(Octopus.PubSub) do
      start_supervised!({Phoenix.PubSub, name: Octopus.PubSub})
    end

    for mod <- [Recording.PanelRecorder, Recording.RadarRecorder, Recording.Session] do
      unless Process.whereis(mod), do: start_supervised!(mod)
    end

    _ = Recording.stop()
    on_exit(fn -> _ = Recording.stop() end)

    :ok
  end

  test "coordinates panel and radar recorders into a shared session directory" do
    base = Path.join(System.tmp_dir!(), "octorec-session-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf(base) end)

    assert {:ok, info} = Recording.start(dir: base, radar: true)

    assert String.starts_with?(info.dir, base)
    assert "file:" <> panels_path = info.panels
    assert "file:" <> radar_path = info.radar
    assert Path.dirname(panels_path) == info.dir
    assert Path.basename(panels_path) == "panels.octorec"
    assert Path.basename(radar_path) == "radar.jsonl"

    status = Recording.status()
    assert status.active
    assert status.panels.active
    assert status.radar.active

    assert :ok = Recording.stop()

    assert File.regular?(panels_path)
    assert File.regular?(radar_path)
    refute Recording.status().active
  end

  test "radar: false records panels only" do
    base = Path.join(System.tmp_dir!(), "octorec-session-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf(base) end)

    assert {:ok, info} = Recording.start(dir: base, radar: false)
    assert info.radar == nil
    assert "file:" <> _ = info.panels

    status = Recording.status()
    assert status.panels.active
    refute status.radar.active

    assert :ok = Recording.stop()
  end

  test "start twice returns already_recording" do
    base = Path.join(System.tmp_dir!(), "octorec-session-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf(base) end)

    assert {:ok, _} = Recording.start(dir: base, radar: false)
    assert {:error, :already_recording} = Recording.start(dir: base, radar: false)
  end
end
