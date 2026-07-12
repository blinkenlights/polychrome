defmodule Octopus.Recording.RadarEncoderTest do
  use ExUnit.Case, async: true

  alias Octopus.Recording.{RadarEncoder, RadarFormat}
  alias Octopus.Radar.Track

  describe "scope_frames/2" do
    test "merges the latest frame from each sensor at each tick" do
      frames = [
        %{t: 0, dev: 1, n: 1, tracks: [%{id: 1, x: 0.0, y: 0.0}]},
        %{t: 0, dev: 2, n: 1, tracks: [%{id: 2, x: 1.0, y: 1.0}]},
        %{t: 100, dev: 1, n: 2, tracks: []}
      ]

      # fps 10 -> dt 100 -> ticks 0, 100
      assert [{0, t0}, {100, t100}] = RadarEncoder.scope_frames(frames, 10)

      assert length(t0) == 2
      # dev 1 cleared its track at t=100; dev 2 still holds its last frame.
      assert length(t100) == 1
      assert [%{id: 2}] = t100
    end

    test "empty input yields no scenes" do
      assert RadarEncoder.scope_frames([], 30) == []
    end
  end

  describe "world_to_px/4" do
    test "maps the origin to the image center" do
      assert RadarEncoder.world_to_px(0.0, 0.0, 10.0, 100) == {50, 50}
    end

    test "maps +x to the right edge and +y to the top" do
      assert {99, 50} = RadarEncoder.world_to_px(10.0, 0.0, 10.0, 100)
      assert {50, 0} = RadarEncoder.world_to_px(0.0, 10.0, 10.0, 100)
    end

    test "clamps out-of-range positions to the edges" do
      assert {99, 99} = RadarEncoder.world_to_px(100.0, -100.0, 10.0, 100)
    end
  end

  test "render/3 produces an rgb24 frame of the requested size" do
    bin = RadarEncoder.render([%{id: 1, x: 0.0, y: 0.0}], 8.0, 32)
    assert byte_size(bin) == 32 * 32 * 3
  end

  @tag :ffmpeg
  test "encode/2 produces a scope video" do
    unless RadarEncoder.ffmpeg_available?() do
      IO.puts("skipping: ffmpeg not available")
    else
      meta = RadarFormat.meta_line(0, 8.0)

      frames =
        for t <- 0..29, into: "" do
          track = %Track{
            id: rem(t, 3),
            reserved: 0,
            x: :math.sin(t / 5.0) * 3.0,
            y: :math.cos(t / 5.0) * 3.0,
            z: 0.0,
            vx: 0.0,
            vy: 0.0,
            vz: 0.0
          }

          RadarFormat.frame_line(t * 33, 1, t, [track])
        end

      base =
        Path.join(System.tmp_dir!(), "octorec-radar-enc-#{System.unique_integer([:positive])}")

      input = base <> ".jsonl"
      out_dir = base <> "_out"
      File.write!(input, meta <> frames)

      on_exit(fn ->
        File.rm(input)
        File.rm_rf(out_dir)
      end)

      assert {:ok, [out]} = RadarEncoder.encode(input, out: out_dir, fps: 10, size: 64)
      assert File.regular?(out)
      assert File.stat!(out).size > 0
    end
  end
end
