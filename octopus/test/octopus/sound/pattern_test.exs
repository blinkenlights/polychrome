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
        |> Pattern.configure_slot(2, %{
          trigger: Pattern.probe_trigger(),
          channel: %{mode: :follow_probe}
        })
        |> Pattern.configure_slot(3, %{
          trigger: %{kind: :held},
          channel: %{mode: :fixed, panel: 9}
        })

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

    test "a composition saved before slots had triggers reads as grid slots" do
      old = %{
        "steps" => 16,
        "slots" => [
          %{
            "id" => 1,
            "name" => "Slot 1",
            "synth" => "pc_ping",
            "note" => 62,
            "duration_ms" => 300,
            "muted" => false,
            "steps" => %{"0" => %{"panel" => 4, "velocity" => 0.7}}
          }
        ]
      }

      pattern = Pattern.from_map(old)

      assert [slot] = pattern.slots
      assert slot.trigger == %{kind: :grid}
      assert slot.channel == %{mode: :step}
      assert [%{channel: 4}] = Pattern.notes_for(pattern, 0)
    end
  end

  describe "triggers and places" do
    test "a fresh slot is played by the grid, on the step's panel" do
      slot = Pattern.new() |> Map.fetch!(:slots) |> hd()

      assert slot.trigger == %{kind: :grid}
      assert slot.channel == %{mode: :step}
    end

    test "only grid slots answer notes_for/2 — the others have their own owner" do
      pattern =
        Pattern.new()
        |> Pattern.put_step(1, 0, 3)
        |> Pattern.put_step(2, 0, 5)
        |> Pattern.configure_slot(2, %{trigger: Pattern.probe_trigger()})

      assert [%{channel: 3}] = Pattern.notes_for(pattern, 0)
      assert [%{id: 2}] = Pattern.probe_slots(pattern)
    end

    test "held and probe slots are found even without a single step" do
      pattern =
        Pattern.new()
        |> Pattern.configure_slot(1, %{trigger: %{kind: :held}})
        |> Pattern.configure_slot(2, %{trigger: Pattern.probe_trigger()})

      assert [%{id: 1}] = Pattern.held_slots(pattern)
      assert [%{id: 2}] = Pattern.probe_slots(pattern)
    end

    test "a muted slot is not offered to its trigger" do
      pattern =
        Pattern.new()
        |> Pattern.configure_slot(1, %{trigger: %{kind: :held}})
        |> Pattern.toggle_mute(1)

      assert Pattern.held_slots(pattern) == []
    end
  end

  describe "channels_for/4" do
    defp slot_with(channel), do: %{channel: channel}

    test "step and follow_probe take the panel they are handed" do
      assert Pattern.channels_for(slot_with(%{mode: :step}), 7) == [7]
      assert Pattern.channels_for(slot_with(%{mode: :follow_probe}), 7) == [7]
    end

    test "fixed ignores it" do
      assert Pattern.channels_for(slot_with(%{mode: :fixed, panel: 3}), 7) == [3]
    end

    test "all_panels spreads one trigger across the ring" do
      assert Pattern.channels_for(slot_with(%{mode: :all_panels}), 7, 0, 4) == [1, 2, 3, 4]
    end

    test "rotate walks on by one place each time it fires" do
      slot = slot_with(%{mode: :rotate, step: 1})

      assert Pattern.channels_for(slot, 1, 0, 4) == [1]
      assert Pattern.channels_for(slot, 1, 1, 4) == [2]
      assert Pattern.channels_for(slot, 1, 4, 4) == [1]
    end

    test "a slot on all panels plays a note per panel from one step" do
      pattern =
        Pattern.new()
        |> Pattern.put_step(1, 0, 1)
        |> Pattern.configure_slot(1, %{channel: %{mode: :all_panels}})

      assert Pattern.notes_for(pattern, 0, 4) |> Enum.map(& &1.channel) == [1, 2, 3, 4]
    end
  end

  describe "pitch_for/2" do
    test "a plain slot sounds its root wherever it is placed" do
      slot = Pattern.new() |> Map.fetch!(:slots) |> hd()

      assert Pattern.pitch_for(slot, 1) == slot.note
      assert Pattern.pitch_for(slot, 7) == slot.note
    end

    test "a scale turns the ring into a voicing" do
      slot = %{note: 62, scale: [0, 2, 3]}

      assert Pattern.pitch_for(slot, 1) == 62
      assert Pattern.pitch_for(slot, 2) == 64
      assert Pattern.pitch_for(slot, 3) == 65
      # Past the end of the scale it rises by an octave rather than repeating.
      assert Pattern.pitch_for(slot, 4) == 74
    end

    test "twelve panels get twelve pitches with the drone voicing" do
      slot = %{note: 38, scale: Pattern.drone_voicing()}
      pitches = Enum.map(1..12, &Pattern.pitch_for(slot, &1))

      assert length(Enum.uniq(pitches)) == 12
    end
  end

  describe "presets" do
    test "as_chase makes a slot the picture sets off, where the wave is" do
      pattern = Pattern.new() |> Pattern.as_chase(1)
      slot = hd(pattern.slots)

      assert slot.trigger.kind == :probe
      assert slot.channel == %{mode: :follow_probe}
      assert [^slot] = Pattern.probe_slots(pattern)
      # It stays out of the grid's way.
      assert Pattern.notes_for(pattern, 0) == []
    end

    test "as_drone makes a held slot on every panel" do
      pattern = Pattern.new() |> Pattern.as_drone(2)
      slot = Enum.at(pattern.slots, 1)

      assert slot.trigger == %{kind: :held}
      assert slot.channel == %{mode: :all_panels}
      assert Pattern.channels_for(slot, 1, 0, 12) == Enum.to_list(1..12)
      assert [^slot] = Pattern.held_slots(pattern)
    end

    test "two chases side by side — the thing that was impossible before" do
      pattern =
        Pattern.new()
        |> Pattern.as_chase(1, synth: "pc_ping", note: 62)
        |> Pattern.as_chase(2, synth: "pc_pluck", note: 38, duration_ms: 1500)

      assert [first, second] = Pattern.probe_slots(pattern)
      assert first.synth == "pc_ping"
      assert second.synth == "pc_pluck"
    end

    test "free_slot finds the first one with nothing to do" do
      pattern = Pattern.new() |> Pattern.as_chase(1) |> Pattern.put_step(2, 0, 1)

      assert Pattern.free_slot(pattern) == 3
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
