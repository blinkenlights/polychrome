defmodule Octopus.Sound.PatternTest do
  use ExUnit.Case, async: true

  alias Octopus.Sound.Pattern

  describe "put_step/4" do
    test "sets a step on the given panel" do
      pattern = Pattern.new() |> Pattern.put_step(1, 0, 5)

      assert [%{channel: 5}] = Pattern.notes_for(pattern, 0)
    end

    test "the same panel again clears the step — one gesture for both" do
      pattern =
        Pattern.new()
        |> Pattern.put_step(1, 0, 5)
        |> Pattern.put_step(1, 0, 5)

      assert Pattern.notes_for(pattern, 0) == []
    end

    test "a different panel moves the step rather than clearing it" do
      pattern =
        Pattern.new()
        |> Pattern.put_step(1, 0, 5)
        |> Pattern.put_step(1, 0, 9)

      assert [%{channel: 9}] = Pattern.notes_for(pattern, 0)
    end
  end

  describe "notes_for/2" do
    test "wraps an absolute step counter into the loop" do
      pattern = Pattern.new(steps: 16) |> Pattern.put_step(1, 3, 2)

      assert [%{channel: 2}] = Pattern.notes_for(pattern, 3)
      assert [%{channel: 2}] = Pattern.notes_for(pattern, 19)
      assert [%{channel: 2}] = Pattern.notes_for(pattern, 35)
      assert Pattern.notes_for(pattern, 4) == []
    end

    test "handles a negative step counter, as a transport before its start would give" do
      pattern = Pattern.new(steps: 16) |> Pattern.put_step(1, 15, 2)

      assert [%{channel: 2}] = Pattern.notes_for(pattern, -1)
    end

    test "collects every slot that has something on this step" do
      pattern =
        Pattern.new()
        |> Pattern.put_step(1, 0, 1)
        |> Pattern.put_step(2, 0, 7)
        |> Pattern.put_step(3, 1, 4)

      assert [%{channel: 1}, %{channel: 7}] = Pattern.notes_for(pattern, 0)
    end

    test "a muted slot stays silent but keeps its steps" do
      pattern =
        Pattern.new()
        |> Pattern.put_step(1, 0, 1)
        |> Pattern.toggle_mute(1)

      assert Pattern.notes_for(pattern, 0) == []

      assert Pattern.notes_for(Pattern.toggle_mute(pattern, 1), 0) == [
               %{channel: 1, note: 62, velocity: 0.7, duration_ms: 300, synth: "pc_ping"}
             ]
    end

    test "carries the slot's sound, not just its position" do
      pattern =
        Pattern.new()
        |> Pattern.configure_slot(1, %{synth: "pc_drone", note: 48, duration_ms: 2000})
        |> Pattern.put_step(1, 0, 1)

      assert [%{synth: "pc_drone", note: 48, duration_ms: 2000}] = Pattern.notes_for(pattern, 0)
    end
  end

  describe "source/1" do
    test "is what the scheduler asks for, one step at a time" do
      pattern = Pattern.new() |> Pattern.put_step(1, 2, 6)
      source = Pattern.source(pattern)

      assert [%{channel: 6}] = source.(%{index: 2, beats: 0.5}, nil)
      assert source.(%{index: 3, beats: 0.75}, nil) == []
    end
  end

  describe "clearing" do
    test "clear_slot empties one row and leaves the others" do
      pattern =
        Pattern.new()
        |> Pattern.put_step(1, 0, 1)
        |> Pattern.put_step(2, 0, 2)
        |> Pattern.clear_slot(1)

      assert [%{channel: 2}] = Pattern.notes_for(pattern, 0)
    end

    test "a fresh pattern is empty" do
      assert Pattern.empty?(Pattern.new())
      refute Pattern.new() |> Pattern.put_step(1, 0, 1) |> Pattern.empty?()
    end
  end

  describe "serialisation" do
    test "survives a round trip through plain maps" do
      pattern =
        Pattern.new(slots: 3, steps: 8)
        |> Pattern.put_step(1, 0, 4)
        |> Pattern.put_step(2, 5, 11)
        |> Pattern.toggle_mute(3)
        |> Pattern.configure_slot(1, %{name: "Kick", synth: "pc_click"})

      restored = pattern |> Pattern.to_map() |> Pattern.from_map()

      assert restored == pattern
    end

    test "string keys survive the database, which is where the map has been" do
      encoded = Pattern.new() |> Pattern.put_step(1, 3, 7) |> Pattern.to_map()
      through_json = encoded |> Jason.encode!() |> Jason.decode!()

      assert [%{channel: 7}] = through_json |> Pattern.from_map() |> Pattern.notes_for(3)
    end

    test "broken input falls back to an empty grid rather than crashing the studio" do
      assert Pattern.from_map(nil) |> Pattern.empty?()
      assert Pattern.from_map(%{"nonsense" => true}) |> Pattern.empty?()
    end
  end

  describe "max_panel/1" do
    test "reports the highest panel in use" do
      pattern =
        Pattern.new()
        |> Pattern.put_step(1, 0, 3)
        |> Pattern.put_step(2, 1, 11)

      assert Pattern.max_panel(pattern) == 11
      assert Pattern.max_panel(Pattern.new()) == 0
    end
  end
end
