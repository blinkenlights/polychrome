defmodule Octopus.Recording.Sink.GzipTest do
  use ExUnit.Case, async: true

  alias Octopus.Recording.Sink

  test "gzip sink produces a standard gzip file that round-trips the bytes" do
    path = Path.join(System.tmp_dir!(), "gzip-sink-#{System.unique_integer([:positive])}.bin.gz")
    on_exit(fn -> File.rm(path) end)

    payload = :binary.copy("the quick brown fox ", 5000)

    {:ok, sink} =
      Sink.Gzip.open(inner_mod: Sink.File, inner_opts: [path: path], level: 6, flush_every: 3)

    {:ok, sink} = Sink.Gzip.write(sink, "HEADER")

    sink =
      Enum.reduce(1..10, sink, fn _, s ->
        {:ok, s} = Sink.Gzip.write(s, payload)
        s
      end)

    assert :ok = Sink.Gzip.close(sink)

    compressed = File.read!(path)
    expected = "HEADER" <> :binary.copy(payload, 10)

    # Standard gzip: readable by :zlib.gunzip, and much smaller than the input.
    assert :zlib.gunzip(compressed) == expected
    assert byte_size(compressed) < byte_size(expected)
  end

  describe "wrap/4" do
    test "returns the sink unchanged when compression is disabled" do
      assert Sink.Gzip.wrap(Sink.File, [path: "/x/y.octorec"], false) ==
               {Sink.File, [path: "/x/y.octorec"]}
    end

    test "wraps a file sink and adds a .gz suffix to the path" do
      assert {Sink.Gzip, opts} = Sink.Gzip.wrap(Sink.File, [path: "/x/y.octorec"], true, 4)
      assert opts[:inner_mod] == Sink.File
      assert opts[:inner_opts][:path] == "/x/y.octorec.gz"
      assert opts[:level] == 4
    end

    test "does not double up the .gz suffix" do
      assert {Sink.Gzip, opts} = Sink.Gzip.wrap(Sink.File, [path: "/x/y.octorec.gz"], true)
      assert opts[:inner_opts][:path] == "/x/y.octorec.gz"
    end

    test "wraps a remote sink without touching its options" do
      assert {Sink.Gzip, opts} =
               Sink.Gzip.wrap(Sink.Remote, [host: "h", port: 1], true)

      assert opts[:inner_mod] == Sink.Remote
      assert opts[:inner_opts] == [host: "h", port: 1]
    end
  end
end
