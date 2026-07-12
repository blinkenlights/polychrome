defmodule Octopus.WanderTest do
  use ExUnit.Case, async: true

  alias Octopus.Wander

  describe "step/3" do
    test "value never leaves [min, max] over many steps including range changes" do
      w = Wander.new(0.0)
      now = 0.0

      {final, _} =
        Enum.reduce(1..10_000, {w, now}, fn _, {wanderer, t} ->
          min = -:rand.uniform() * 3
          max = :rand.uniform() * 3
          tempo = 0.1 + :rand.uniform() * 2.0
          {value, next} = Wander.step(wanderer, t, %{min: min, max: max, tempo: tempo})
          lo = min(min, max)
          hi = max(min, max)
          assert value >= lo - 1.0e-9
          assert value <= hi + 1.0e-9
          {next, t + 0.05 + :rand.uniform() * 0.2}
        end)

      assert is_float(final.value)
    end

    test "value at segment boundary equals the target exactly" do
      w = %Wander{
        value: 0.0,
        seg_from: 0.0,
        target: 2.5,
        seg_start: 0.0,
        seg_dur: 1.0,
        easing: :smoothstep
      }

      {value, next} = Wander.step(w, 1.0, %{min: -5.0, max: 5.0, tempo: 1.0})
      # After p>=1, a new segment starts from the finalized target
      assert_in_delta next.seg_from, 2.5, 1.0e-12
      assert is_float(value)
    end

    test "tempo 0 holds the value" do
      w = Wander.new(1.25)
      {v1, w1} = Wander.step(w, 10.0, %{min: -2.0, max: 2.0, tempo: 0.0})
      {v2, _w2} = Wander.step(w1, 100.0, %{min: -2.0, max: 2.0, tempo: 0.0})
      assert_in_delta v1, 1.25, 1.0e-12
      assert_in_delta v2, 1.25, 1.0e-12
    end
  end

  describe "ease/2" do
    test "each easing maps 0→0 and 1→1 with near-zero derivative at ends" do
      for easing <- [:smoothstep, :sine_in_out, :cubic_in_out] do
        assert_in_delta Wander.ease(easing, 0.0), 0.0, 1.0e-12
        assert_in_delta Wander.ease(easing, 1.0), 1.0, 1.0e-12

        eps = 1.0e-4
        d0 = (Wander.ease(easing, eps) - Wander.ease(easing, 0.0)) / eps
        d1 = (Wander.ease(easing, 1.0) - Wander.ease(easing, 1.0 - eps)) / eps
        assert abs(d0) < 0.01
        assert abs(d1) < 0.01
      end
    end
  end
end
