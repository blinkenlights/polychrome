defmodule Octopus.Sound.TimelineTest do
  use ExUnit.Case, async: true

  alias Octopus.Sound.Timeline

  defp timeline(opts \\ []) do
    Timeline.new(Keyword.merge([bpm: 120.0, anchor_ms: 0], opts))
  end

  describe "beats_at/2" do
    test "a stopped timeline stays where it is" do
      timeline = timeline()

      assert Timeline.beats_at(timeline, 0) == 0.0
      assert Timeline.beats_at(timeline, 10_000) == 0.0
    end

    test "counts beats from the anchor while playing" do
      # 120 bpm is exactly two beats per second.
      timeline = timeline() |> Timeline.play(0)

      assert Timeline.beats_at(timeline, 500) == 1.0
      assert Timeline.beats_at(timeline, 2_000) == 4.0
    end
  end

  describe "play/stop" do
    test "stopping keeps the position and resuming continues from it" do
      timeline = timeline() |> Timeline.play(0) |> Timeline.stop(1_000)

      assert Timeline.beats_at(timeline, 1_000) == 2.0
      # Time passing while stopped must not move the playhead.
      assert Timeline.beats_at(timeline, 9_000) == 2.0

      timeline = Timeline.play(timeline, 9_000)
      assert Timeline.beats_at(timeline, 9_500) == 3.0
    end

    test "playing an already playing timeline is a no-op" do
      timeline = timeline() |> Timeline.play(0)

      assert Timeline.play(timeline, 5_000) == timeline
    end
  end

  describe "set_bpm/3" do
    test "does not move the playhead" do
      timeline = timeline() |> Timeline.play(0)
      before = Timeline.beats_at(timeline, 1_000)

      timeline = Timeline.set_bpm(timeline, 1_000, 60)

      assert Timeline.beats_at(timeline, 1_000) == before
      # Half the tempo, so half the beats in the next second.
      assert Timeline.beats_at(timeline, 2_000) == before + 1.0
    end
  end

  describe "ms_at/2" do
    test "is the inverse of beats_at/2" do
      timeline = timeline(bpm: 93.0) |> Timeline.play(1_234)

      for beats <- [0.25, 4.0, 37.5] do
        assert_in_delta Timeline.beats_at(timeline, Timeline.ms_at(timeline, beats)),
                        beats,
                        1.0e-9
      end
    end
  end

  describe "position/2" do
    test "bar, beat and step are 1-based and wrap into the loop" do
      timeline = timeline(beats_per_bar: 4, steps_per_beat: 4, loop_bars: 2) |> Timeline.play(0)

      assert %{bar: 1, beat: 1, step: 1} = Timeline.position(timeline, 0)
      # 4.75 beats: second bar, first beat, last sixteenth.
      assert %{bar: 2, beat: 1, step: 4} = Timeline.position(timeline, 2_375)
      # 8 beats is a full loop of two 4/4 bars, so we are back at the start.
      assert %{bar: 1, beat: 1, step: 1} = Timeline.position(timeline, 4_000)
    end

    test "reports absolute beats alongside the looped position" do
      timeline = timeline(loop_bars: 1) |> Timeline.play(0)

      position = Timeline.position(timeline, 3_000)

      assert %{bar: 1, beat: 3} = position
      assert position.beats == 6.0
      assert position.loop_beats == 2.0
    end
  end

  describe "steps_between/3" do
    test "returns the steps in the half-open range" do
      timeline = timeline(steps_per_beat: 4)

      assert [%{index: 1, beats: 0.25}, %{index: 2, beats: 0.5}] =
               Timeline.steps_between(timeline, 0.0, 0.5)
    end

    test "consecutive windows cover every step exactly once" do
      timeline = timeline(steps_per_beat: 4)

      marks = [0.0, 0.3, 0.55, 0.9, 2.0]

      indexes =
        marks
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.flat_map(fn [from, to] ->
          timeline |> Timeline.steps_between(from, to) |> Enum.map(& &1.index)
        end)

      assert indexes == Enum.to_list(1..8)
    end

    test "is empty when no step boundary falls inside the window" do
      timeline = timeline(steps_per_beat: 4)

      assert Timeline.steps_between(timeline, 0.26, 0.49) == []
    end
  end
end
