defmodule Octopus.Recording.PanelRecorderTest do
  use ExUnit.Case, async: false

  alias Octopus.{Installation, Recording}
  alias Octopus.Recording.Format
  alias Octopus.Protobuf.{RGBFrame, WFrame}

  @mixer_topic "mixer"

  setup do
    # These are part of the running application; make sure they exist even if
    # the app was not started for the test run.
    unless Process.whereis(Octopus.PubSub) do
      start_supervised!({Phoenix.PubSub, name: Octopus.PubSub})
    end

    unless Process.whereis(Recording.PanelRecorder) do
      start_supervised!(Recording.PanelRecorder)
    end

    # Ensure we begin idle regardless of what previous tests did.
    _ = Recording.stop()
    on_exit(fn -> _ = Recording.stop() end)

    :ok
  end

  test "records mixer frames to an append-only file, dedups split parts and normalizes W frames" do
    dir = Path.join(System.tmp_dir!(), "octorec-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf(dir) end)

    num_panels = Installation.num_panels()
    pw = Installation.panel_width()
    ph = Installation.panel_height()
    rgb_size = num_panels * pw * ph * 3
    w_size = num_panels * pw * ph

    frame_a = %RGBFrame{data: :binary.copy(<<11>>, rgb_size)}
    frame_b = %RGBFrame{data: :binary.copy(<<22>>, rgb_size)}
    wframe = %WFrame{data: :binary.copy(<<50>>, w_size)}

    expected_a = frame_a.data
    expected_b = frame_b.data
    expected_w = :binary.copy(<<50>>, rgb_size)

    assert {:ok, "file:" <> path} = Recording.start(dir: dir)

    # A duplicate immediately follows A (as the mixer does per UDP split part)
    # and must be de-duplicated.
    broadcast(frame_a)
    broadcast(frame_a)
    broadcast(frame_b)
    broadcast(wframe)

    # stop/0 is a synchronous call to the recorder; all frames broadcast before
    # it are guaranteed to have been processed by the time it returns.
    assert :ok = Recording.stop()

    assert {:ok, header, records} = Format.parse(File.read!(path))
    assert header.num_panels == num_panels
    assert header.panel_width == pw
    assert header.panel_height == ph

    # Filter to the frames this test produced (the running mixer may also emit
    # blank idle frames onto the same topic).
    distinctive =
      records
      |> Enum.map(fn {_offset, data} -> data end)
      |> Enum.filter(&(&1 in [expected_a, expected_b, expected_w]))

    assert distinctive == [expected_a, expected_b, expected_w]
  end

  test "status reflects active/idle state" do
    dir = Path.join(System.tmp_dir!(), "octorec-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf(dir) end)

    assert %{active: false} = Recording.status()

    assert {:ok, _target} = Recording.start(dir: dir)
    status = Recording.status()
    assert status.active == true
    assert status.num_panels == Installation.num_panels()

    assert :ok = Recording.stop()
    assert %{active: false} = Recording.status()
  end

  test "start/1 twice returns already_recording" do
    dir = Path.join(System.tmp_dir!(), "octorec-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf(dir) end)

    assert {:ok, _} = Recording.start(dir: dir)
    assert {:error, :already_recording} = Recording.start(dir: dir)
  end

  defp broadcast(frame) do
    Phoenix.PubSub.broadcast(Octopus.PubSub, @mixer_topic, {:mixer, {:frame, frame}})
  end
end
