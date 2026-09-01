defmodule Octopus.Sound.DroneTest do
  use ExUnit.Case, async: false

  alias Octopus.Sound.{Drone, Engine, Probes}

  describe "amplitude/2" do
    test "only the bright half of the formula sounds" do
      assert Drone.amplitude(1.0, 1.0) == 1.0
      assert Drone.amplitude(0.5, 1.0) == 0.5
      assert Drone.amplitude(-0.5, 1.0) == 0.0
    end

    test "gain scales it" do
      assert Drone.amplitude(1.0, 0.4) == 0.4
    end
  end

  describe "voices" do
    setup do
      previous = Application.get_env(:octopus, Octopus.Sound, [])

      Application.put_env(
        :octopus,
        Octopus.Sound,
        Keyword.merge(previous, engine: Engine.Recorder, channels: 4)
      )

      Engine.Recorder.attach()

      on_exit(fn ->
        Engine.Recorder.detach()
        Application.put_env(:octopus, Octopus.Sound, previous)
      end)

      %{drone: start_supervised!({Drone, enabled: false})}
    end

    test "starts one voice per panel, silent, and lets them go again", %{drone: drone} do
      Drone.enable(true)

      for index <- 0..3 do
        assert_receive {:voice, {:drone, ^index}, params}
        assert params.channel == index + 1
        assert params.amp == 0.0
      end

      Drone.enable(false)
      assert_receive {:release, {:drone, 0}}

      _ = :sys.get_state(drone)
    end

    test "a bright panel makes its voice audible" do
      Drone.enable(true)
      Drone.configure(gain: 1.0)

      Probes.broadcast([1.0, -1.0, 0.5, 0.0], 0.0)

      assert_receive {:set_voice, {:drone, 0}, %{amp: 1.0}}
      assert_receive {:set_voice, {:drone, 1}, %{amp: +0.0}}
      assert_receive {:set_voice, {:drone, 2}, %{amp: 0.5}}
    end

    test "a stopped drone ignores the picture" do
      Probes.broadcast([1.0, 1.0, 1.0, 1.0], 0.0)

      refute_receive {:set_voice, _, _}, 100
    end
  end
end
