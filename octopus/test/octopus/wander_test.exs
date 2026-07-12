defmodule Octopus.WanderTest do
  use ExUnit.Case, async: true

  alias Octopus.Wander

  describe "step/3 scalar" do
    test "value never leaves [min, max] over many steps including range changes" do
      w = Wander.new(0.0)
      now = 0.0

      {final, _} =
        Enum.reduce(1..10_000, {w, now}, fn _, {wanderer, t} ->
          min = -:rand.uniform() * 3
          max = :rand.uniform() * 3
          interval = 4.0 + :rand.uniform() * 20.0
          {value, next} = Wander.step(wanderer, t, %{min: min, max: max, interval: interval})
          lo = min(min, max)
          hi = max(min, max)
          assert value >= lo - 1.0e-9
          assert value <= hi + 1.0e-9
          {next, t + 0.05 + :rand.uniform() * 0.2}
        end)

      assert is_float(elem(final.value, 0))
    end

    test "value at segment boundary equals the target exactly" do
      w = %Wander{
        value: {0.0},
        seg_from: {0.0},
        target: {2.5},
        seg_start: 0.0,
        seg_dur: 1.0,
        easing: :smoothstep
      }

      {value, next} = Wander.step(w, 1.0, %{min: -5.0, max: 5.0, interval: 10.0})
      assert_in_delta next.seg_from |> elem(0), 2.5, 1.0e-12
      assert is_float(value)
    end

    test "interval 0 holds the value" do
      w = Wander.new(1.25)
      {v1, w1} = Wander.step(w, 10.0, %{min: -2.0, max: 2.0, interval: 0.0})
      {v2, _w2} = Wander.step(w1, 100.0, %{min: -2.0, max: 2.0, interval: 0.0})
      assert_in_delta v1, 1.25, 1.0e-12
      assert_in_delta v2, 1.25, 1.0e-12
    end
  end

  describe "step/3 vector" do
    test "both dimensions reach the segment target at the same instant" do
      w = %Wander{
        value: {0.0, 0.0},
        seg_from: {0.0, 0.0},
        target: {4.0, -2.0},
        seg_start: 0.0,
        seg_dur: 2.0,
        easing: :smoothstep
      }

      {v_mid, _} =
        Wander.step(w, 1.0, %{mins: {-5.0, -5.0}, maxs: {5.0, 5.0}, interval: 10.0})

      # Midpoint of smoothstep at p=0.5 is 0.5
      assert_in_delta elem(v_mid, 0), 2.0, 1.0e-9
      assert_in_delta elem(v_mid, 1), -1.0, 1.0e-9

      {v_end, next} =
        Wander.step(w, 2.0, %{mins: {-5.0, -5.0}, maxs: {5.0, 5.0}, interval: 10.0})

      assert_in_delta elem(v_end, 0), 4.0, 1.0e-12
      assert_in_delta elem(v_end, 1), -2.0, 1.0e-12
      assert_in_delta elem(next.seg_from, 0), 4.0, 1.0e-12
      assert_in_delta elem(next.seg_from, 1), -2.0, 1.0e-12
    end

    test "intermediate values are collinear with segment endpoints" do
      from = {1.0, 2.0}
      target = {5.0, -2.0}

      w = %Wander{
        value: from,
        seg_from: from,
        target: target,
        seg_start: 0.0,
        seg_dur: 1.0,
        easing: :smoothstep
      }

      for t <- [0.1, 0.3, 0.5, 0.7, 0.9] do
        {v, _} = Wander.step(w, t, %{mins: {-10.0, -10.0}, maxs: {10.0, 10.0}, interval: 10.0})
        dx = elem(target, 0) - elem(from, 0)
        dy = elem(target, 1) - elem(from, 1)
        # (v - from) cross (target - from) == 0
        cross =
          (elem(v, 0) - elem(from, 0)) * dy - (elem(v, 1) - elem(from, 1)) * dx

        assert_in_delta cross, 0.0, 1.0e-9
      end
    end

    test "per-dimension bounds hold over 10k steps" do
      w = Wander.new({0.0, 0.0})
      now = 0.0

      Enum.reduce(1..10_000, {w, now}, fn _, {wanderer, t} ->
        mins = {-:rand.uniform() * 3, -:rand.uniform() * 2}
        maxs = {:rand.uniform() * 3, :rand.uniform() * 2}
        interval = 4.0 + :rand.uniform() * 10.0

        {value, next} =
          Wander.step(wanderer, t, %{mins: mins, maxs: maxs, interval: interval})

        for i <- 0..1 do
          lo = min(elem(mins, i), elem(maxs, i))
          hi = max(elem(mins, i), elem(maxs, i))
          assert elem(value, i) >= lo - 1.0e-9
          assert elem(value, i) <= hi + 1.0e-9
        end

        {next, t + 0.05 + :rand.uniform() * 0.2}
      end)
    end

    test "mean segment duration ≈ interval * 1.05 within 10%" do
      interval = 10.0
      w = Wander.new(0.0)
      now = 0.0
      sample_count = 200

      {durs, _} =
        Enum.reduce(1..sample_count, {[], {w, now}}, fn _, {acc, {wanderer, t}} ->
          # Force a fresh segment by jumping past current seg_dur
          t2 =
            case wanderer.seg_start do
              :pending -> t
              start -> start + wanderer.seg_dur + 0.001
            end

          {_v, next} = Wander.step(wanderer, t2, %{min: -5.0, max: 5.0, interval: interval})
          {[next.seg_dur | acc], {next, t2}}
        end)

      mean = Enum.sum(durs) / length(durs)
      expected = interval * 1.05
      assert_in_delta mean, expected, expected * 0.10
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
