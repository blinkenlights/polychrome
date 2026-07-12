defmodule Octopus.Recording.EncoderTest do
  use ExUnit.Case, async: true

  alias Octopus.Recording.{Encoder, Format}

  describe "resample/2" do
    test "holds the most recent frame at each fixed tick" do
      records = [{0, "A"}, {100, "B"}, {250, "C"}]
      # fps 10 -> dt 100ms -> ticks at 0, 100, 200
      assert Encoder.resample(records, 10) == ["A", "B", "B"]
    end

    test "single record yields a single frame" do
      assert Encoder.resample([{0, "A"}], 30) == ["A"]
    end

    test "empty records yield no frames" do
      assert Encoder.resample([], 30) == []
    end
  end

  test "panel_frame/3 slices a panel's contiguous block" do
    geom = {3, 2, 2}
    block = 2 * 2 * 3
    data = for b <- 0..(3 * block - 1), into: <<>>, do: <<rem(b, 256)>>

    assert Encoder.panel_frame(data, 0, geom) == binary_part(data, 0, block)
    assert Encoder.panel_frame(data, 1, geom) == binary_part(data, block, block)
    assert Encoder.panel_frame(data, 2, geom) == binary_part(data, 2 * block, block)
  end

  test "strip_frame/2 transposes panel-major data into a row-major strip" do
    # 2 panels, 2x2. Each pixel's 3 bytes carry its index 0..7.
    geom = {2, 2, 2}
    data = for i <- 0..7, into: <<>>, do: <<i, i, i>>

    px = fn i -> <<i, i, i>> end

    # Row 0: p0(x0,x1), p1(x0,x1) = 0,1,4,5 ; Row 1: 2,3,6,7
    expected =
      px.(0) <> px.(1) <> px.(4) <> px.(5) <> px.(2) <> px.(3) <> px.(6) <> px.(7)

    assert Encoder.strip_frame(data, geom) == expected
  end

  @tag :ffmpeg
  test "encode/2 produces per-panel and mixed videos" do
    unless Encoder.ffmpeg_available?() do
      # Keep the suite independent of ffmpeg being installed.
      IO.puts("skipping: ffmpeg not available")
    else
      num_panels = 3
      pw = 2
      ph = 2
      frame_bytes = Format.frame_bytes(num_panels, pw, ph)

      frame_a = :binary.copy(<<10>>, frame_bytes)
      frame_b = :binary.copy(<<200>>, frame_bytes)

      binary =
        Format.header(num_panels, pw, ph, 0) <>
          Format.record(0, frame_a) <>
          Format.record(100, frame_b)

      base = Path.join(System.tmp_dir!(), "octorec-enc-#{System.unique_integer([:positive])}")
      input = base <> ".octorec"
      out_dir = base <> "_out"
      File.write!(input, binary)

      on_exit(fn ->
        File.rm(input)
        File.rm_rf(out_dir)
      end)

      assert {:ok, outputs} = Encoder.encode(input, out: out_dir, fps: 10, scale: 4)

      assert length(outputs) == num_panels + 1
      assert Path.join(out_dir, "mixed.mp4") in outputs

      for output <- outputs do
        assert File.regular?(output)
        assert File.stat!(output).size > 0
      end
    end
  end
end
