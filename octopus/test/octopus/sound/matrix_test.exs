defmodule Octopus.Sound.MatrixTest do
  # Not async: the applying tests start the named sound processes.
  use ExUnit.Case, async: false

  alias Octopus.Sound.Matrix

  defp context(overrides \\ []) do
    Enum.into(overrides, %{beats: 0.0, beats_per_bar: 4, probes: [], features: %{}})
  end

  describe "direction/2" do
    test "reads the direction off the two worlds involved" do
      assert Matrix.direction({:feature, :level}, {:scene, :saturation_percent}) ==
               :sound_to_light

      assert Matrix.direction({:probe, :mean}, {:held, :gain}) == :light_to_sound
      assert Matrix.direction({:phase, 8}, {:scene, :zoom_base}) == :score
      assert Matrix.direction({:phase, 8}, {:held, :gain}) == :score
    end
  end

  describe "value/2 — phase" do
    test "goes out and comes back over the given number of bars" do
      phase = fn beats -> Matrix.value({:phase, 4}, context(beats: beats)) end

      assert phase.(0.0) == 0.0
      assert_in_delta phase.(8.0), 1.0, 0.001
      assert_in_delta phase.(15.9), 0.0, 0.05
    end

    test "returning to the start is what keeps a breathing scene from jumping" do
      phase = fn beats -> Matrix.value({:phase, 4}, context(beats: beats)) end

      assert_in_delta phase.(15.99), phase.(0.01), 0.02
    end

    test "stays inside 0..1 well beyond the first loop" do
      for beats <- [0.0, 3.7, 42.0, 1000.25] do
        value = Matrix.value({:phase, 8}, context(beats: beats))
        assert value >= 0.0 and value <= 1.0
      end
    end
  end

  describe "value/2 — probes" do
    test "maps a signed reading onto 0..1" do
      assert Matrix.value({:probe, :mean}, context(probes: [-1.0])) == 0.0
      assert Matrix.value({:probe, :mean}, context(probes: [0.0])) == 0.5
      assert Matrix.value({:probe, :mean}, context(probes: [1.0])) == 1.0
    end

    test "mean and maximum differ on an uneven ring" do
      probes = [-1.0, -1.0, 1.0]

      # mean of -1, -1, 1 is -1/3, which lands a third of the way up.
      assert_in_delta Matrix.value({:probe, :mean}, context(probes: probes)), 0.333, 0.01
      assert Matrix.value({:probe, :max}, context(probes: probes)) == 1.0
    end

    test "no picture yet reads as the middle, not as darkness" do
      assert Matrix.value({:probe, :mean}, context()) == 0.5
    end
  end

  describe "value/2 — features" do
    test "passes the engine's own measurements through" do
      features = %{level: 0.4, onset: 1.0}

      assert Matrix.value({:feature, :level}, context(features: features)) == 0.4
      assert Matrix.value({:feature, :onset}, context(features: features)) == 1.0
    end

    test "a silent engine reads as zero" do
      assert Matrix.value({:feature, :level}, context()) == 0.0
    end
  end

  describe "shape/2" do
    test "exp keeps small values small, which is what an accent wants" do
      assert Matrix.shape(:exp, 0.5) == 0.25
      assert Matrix.shape(:linear, 0.5) == 0.5
      assert Matrix.shape(:inverse, 0.25) == 0.75
    end

    test "every curve stays inside 0..1" do
      for curve <- Matrix.curves(), value <- [0.0, 0.3, 1.0] do
        shaped = Matrix.shape(curve, value)
        assert shaped >= 0.0 and shaped <= 1.0
      end
    end
  end

  describe "applying" do
    # This is the path that only breaks with a real target attached: the first
    # write has nothing to compare against, and comparing against a sentinel
    # that is not a number takes the whole matrix down with it.
    setup do
      start_supervised!({Octopus.Sound.Clock, bpm: 480.0})
      start_supervised!(Octopus.Sound.Patch)
      Octopus.Sound.Patch.update(&Octopus.Sound.Pattern.as_chase(&1, 1))
      start_supervised!(Matrix)
      :ok
    end

    test "moves a real target and keeps running" do
      base = chase_duration()
      Matrix.add({:phase, 4}, {:probe, :duration_ms}, amount: 1.0)
      Octopus.Sound.Clock.play()

      moved? =
        Enum.any?(1..20, fn _ ->
          Process.sleep(60)
          chase_duration() != base
        end)

      assert moved?, "the chase length never moved — the matrix is not writing"
      assert Process.alive?(Process.whereis(Matrix))
    end

    test "removing a row puts the target back where it was" do
      base = chase_duration()
      binding = Matrix.add({:phase, 4}, {:probe, :duration_ms}, amount: 1.0)
      Octopus.Sound.Clock.play()
      Process.sleep(250)

      Matrix.remove(binding.id)

      assert chase_duration() == base
    end

    defp chase_duration do
      Octopus.Sound.Patch.pattern()
      |> Octopus.Sound.Pattern.probe_slots()
      |> hd()
      |> Map.fetch!(:duration_ms)
    end

    test "an unknown source or target is refused rather than stored" do
      assert Matrix.add({:phase, 3}, {:scene, :zoom_base}) == {:error, :unknown}
      assert Matrix.add({:phase, 4}, {:scene, :nonsense}) == {:error, :unknown}
      assert Matrix.list() == []
    end
  end

  describe "the catalogue" do
    test "every source and target has a label and a world it belongs to" do
      for {_key, source} <- Matrix.sources() do
        assert is_binary(source.label)
        assert source.domain in [:light, :sound, :score]
      end

      for {_key, target} <- Matrix.targets() do
        assert is_binary(target.label)
        assert target.domain in [:light, :sound]
        assert target.span > 0
        assert target.min < target.max
      end
    end

    test "all three coupling directions can actually be built from it" do
      pairs =
        for {source, _} <- Matrix.sources(), {target, _} <- Matrix.targets() do
          Matrix.direction(source, target)
        end

      assert :sound_to_light in pairs
      assert :light_to_sound in pairs
      assert :score in pairs
    end
  end
end
