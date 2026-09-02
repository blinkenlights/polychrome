defmodule Octopus.Sound.Trigger.HeldTest do
  use ExUnit.Case, async: false

  alias Octopus.Installation
  alias Octopus.Sound.{Engine, Patch, Pattern, Probes}
  alias Octopus.Sound.Trigger.Held

  describe "amplitude/3" do
    test "only the bright half of the formula sounds" do
      assert Held.amplitude(1.0, 1.0, 1.0) == 1.0
      assert Held.amplitude(0.5, 1.0, 1.0) == 0.5
      assert Held.amplitude(-0.5, 1.0, 1.0) == 0.0
    end

    test "the curve pushes lukewarm panels down and leaves bright ones alone" do
      assert Held.amplitude(1.0, 1.0) == 1.0
      assert Held.amplitude(0.5, 1.0) < 0.35
      assert Held.amplitude(0.5, 1.0) > 0.2
    end
  end

  describe "held slots" do
    setup do
      previous = Application.get_env(:octopus, Octopus.Sound, [])
      previous_installation = Application.get_env(:octopus, :installation)

      # Twelve panels on a machine with two outputs — a voice belongs to a
      # panel, not to an output.
      Application.put_env(:octopus, :installation, Octopus.Installation.Nation2026)

      Application.put_env(
        :octopus,
        Octopus.Sound,
        Keyword.merge(previous, engine: Engine.Recorder, channels: 2)
      )

      Engine.Recorder.attach()

      on_exit(fn ->
        Engine.Recorder.detach()
        Application.put_env(:octopus, Octopus.Sound, previous)
        Application.put_env(:octopus, :installation, previous_installation)
      end)

      start_supervised!(Patch)
      held = start_supervised!(Held)

      %{held: held, panels: Installation.num_panels()}
    end

    test "a drone slot starts one voice per panel, silent", %{panels: panels} do
      Patch.update(&Pattern.as_drone(&1, 1))

      for panel <- 1..panels do
        assert_receive {:voice, {1, ^panel}, params}
        assert params.channel == panel
        assert params.amp == 0.0
      end
    end

    test "each panel gets its own pitch", %{panels: panels} do
      Patch.update(&Pattern.as_drone(&1, 1))

      notes =
        for _ <- 1..panels do
          assert_receive {:voice, _id, params}
          params.note
        end

      assert length(Enum.uniq(notes)) == panels
    end

    test "a bright panel makes its voice audible", %{held: held, panels: panels} do
      Patch.update(&Pattern.as_drone(&1, 1, gain: 1.0))
      _ = :sys.get_state(held)

      values = [1.0, -1.0] ++ List.duplicate(0.0, panels - 2)
      Probes.broadcast(values, 0.0)

      assert_receive {:set_voice, {1, 1}, %{amp: 1.0}}
      assert_receive {:set_voice, {1, 2}, %{amp: +0.0}}
    end

    test "clearing the slot lets every voice go", %{held: held, panels: panels} do
      Patch.update(&Pattern.as_drone(&1, 1))
      _ = :sys.get_state(held)

      Patch.update(&Pattern.configure_slot(&1, 1, %{trigger: Pattern.default_trigger()}))

      for panel <- 1..panels do
        assert_receive {:release, {1, ^panel}}
      end
    end

    test "editing another slot does not disturb the chord", %{held: held} do
      Patch.update(&Pattern.as_drone(&1, 1))
      _ = :sys.get_state(held)
      drain()

      Patch.update(&Pattern.put_step(&1, 2, 0, 3))
      _ = :sys.get_state(held)

      refute_receive {:release, _}, 50
      refute_receive {:voice, _, _}, 50
    end

    test "a muted slot is silent" do
      Patch.update(&(&1 |> Pattern.as_drone(1) |> Pattern.toggle_mute(1)))

      refute_receive {:voice, _, _}, 100
    end
  end

  defp drain do
    receive do
      _ -> drain()
    after
      0 -> :ok
    end
  end
end
