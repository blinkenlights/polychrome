defmodule Octopus.Sound.DroneTest do
  use ExUnit.Case, async: false

  alias Octopus.Installation
  alias Octopus.Sound.{Drone, Engine, Probes}

  describe "amplitude/3" do
    test "only the bright half of the formula sounds" do
      assert Drone.amplitude(1.0, 1.0, 1.0) == 1.0
      assert Drone.amplitude(0.5, 1.0, 1.0) == 0.5
      assert Drone.amplitude(-0.5, 1.0, 1.0) == 0.0
    end

    test "gain scales it" do
      assert Drone.amplitude(1.0, 0.4, 1.0) == 0.4
    end

    test "the curve pushes lukewarm panels down and leaves bright ones alone" do
      # A panel at half brightness should not be half as loud as a bright one,
      # or the voicing disappears into a wash.
      assert Drone.amplitude(1.0, 1.0) == 1.0
      assert Drone.amplitude(0.5, 1.0) < 0.35
      assert Drone.amplitude(0.5, 1.0) > 0.2
    end
  end

  describe "voices" do
    setup do
      previous = Application.get_env(:octopus, Octopus.Sound, [])
      previous_installation = Application.get_env(:octopus, :installation)

      # A ring of twelve panels on a machine with two outputs — the case the
      # drone has to get right, and the one that was wrong.
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

      %{drone: start_supervised!({Drone, enabled: false}), panels: Installation.num_panels()}
    end

    test "one voice per panel, not per output", %{panels: panels} do
      assert panels == 12
      Drone.enable(true)

      for index <- 0..(panels - 1) do
        assert_receive {:voice, {:drone, ^index}, params}
        assert params.channel == index + 1
        assert params.amp == 0.0
      end
    end

    test "lets every voice go again", %{drone: drone, panels: panels} do
      Drone.enable(true)
      Drone.enable(false)

      for index <- 0..(panels - 1) do
        assert_receive {:release, {:drone, ^index}}
      end

      _ = :sys.get_state(drone)
    end

    test "a bright panel makes its voice audible", %{panels: panels} do
      Drone.enable(true)
      Drone.configure(gain: 1.0)

      values = [1.0, -1.0, 0.5] ++ List.duplicate(0.0, panels - 3)
      Probes.broadcast(values, 0.0)

      assert_receive {:set_voice, {:drone, 0}, %{amp: 1.0}}
      assert_receive {:set_voice, {:drone, 1}, %{amp: +0.0}}
      assert_receive {:set_voice, {:drone, 2}, %{amp: quiet}}
      assert quiet < 0.35 and quiet > 0.2
    end

    test "a stopped drone ignores the picture" do
      Probes.broadcast([1.0, 1.0, 1.0, 1.0], 0.0)

      refute_receive {:set_voice, _, _}, 100
    end
  end
end
