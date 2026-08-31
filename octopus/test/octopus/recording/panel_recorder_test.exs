defmodule Octopus.Recording.PanelRecorderTest do
  use ExUnit.Case, async: false

  alias Octopus.{Installation, Recording}
  alias Octopus.Recording.Format
  alias Octopus.Recording.Sink
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

  test "compress: true writes a gzip file that decompresses to a valid recording" do
    dir = Path.join(System.tmp_dir!(), "octorec-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf(dir) end)

    num_panels = Installation.num_panels()
    rgb_size = num_panels * Installation.panel_width() * Installation.panel_height() * 3
    frame_a = %RGBFrame{data: :binary.copy(<<91>>, rgb_size)}
    frame_b = %RGBFrame{data: :binary.copy(<<200>>, rgb_size)}

    assert {:ok, "gzip+file:" <> path} = Recording.start(dir: dir, compress: true)
    assert String.ends_with?(path, ".octorec.gz")

    broadcast(frame_a)
    broadcast(frame_b)
    assert :ok = Recording.stop()

    raw = path |> File.read!() |> :zlib.gunzip()
    assert {:ok, header, records} = Format.parse(raw)
    assert header.num_panels == num_panels

    distinctive =
      records
      |> Enum.map(fn {_o, d} -> d end)
      |> Enum.filter(&(&1 in [frame_a.data, frame_b.data]))

    assert distinctive == [frame_a.data, frame_b.data]
  end

  test "streams the recording to a remote TCP server" do
    {:ok, listen} =
      :gen_tcp.listen(0, [:binary, packet: :raw, active: false, reuseaddr: true])

    {:ok, port} = :inet.port(listen)
    test_pid = self()

    _acceptor =
      spawn_link(fn ->
        {:ok, sock} = :gen_tcp.accept(listen, 2000)
        send(test_pid, {:received, recv_all(sock, <<>>)})
      end)

    num_panels = Installation.num_panels()
    pw = Installation.panel_width()
    ph = Installation.panel_height()
    rgb_size = num_panels * pw * ph * 3

    frame_a = %RGBFrame{data: :binary.copy(<<77>>, rgb_size)}
    frame_b = %RGBFrame{data: :binary.copy(<<123>>, rgb_size)}

    assert {:ok, "tcp://127.0.0.1:" <> _} =
             Recording.start(sink_mod: Sink.Remote, sink_opts: [host: {127, 0, 0, 1}, port: port])

    broadcast(frame_a)
    broadcast(frame_b)

    # Closing the socket on stop lets the server's recv loop finish.
    assert :ok = Recording.stop()

    assert_receive {:received, data}, 2000
    assert {:ok, header, records} = Format.parse(data)
    assert header.num_panels == num_panels

    distinctive =
      records
      |> Enum.map(fn {_offset, d} -> d end)
      |> Enum.filter(&(&1 in [frame_a.data, frame_b.data]))

    assert distinctive == [frame_a.data, frame_b.data]
  end

  defp broadcast(frame) do
    Phoenix.PubSub.broadcast(Octopus.PubSub, @mixer_topic, {:mixer, {:frame, frame}})
  end

  defp recv_all(sock, acc) do
    case :gen_tcp.recv(sock, 0, 2000) do
      {:ok, data} -> recv_all(sock, acc <> data)
      {:error, _} -> acc
    end
  end
end
