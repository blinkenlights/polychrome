defmodule Octopus.Apps.PixelFun3D.ZoomTest do
  use ExUnit.Case, async: true

  alias Octopus.Apps.PixelFun3D.Zoom
  alias Octopus.Sphere

  @r_max 1.47
  @r_min 0.68

  describe "decompose/2" do
    test "z=1 → {0, 1.0}" do
      assert Zoom.decompose(1.0, 0) == {0, 1.0}
    end

    test "monotone sweep 0.7→11: n non-decreasing, r in [1/√2, 1.47]" do
      z_values = for i <- 0..188, do: 0.7 + i * 0.05

      {_n, _r} =
        Enum.reduce(z_values, {0, 1.0}, fn z, {prev_n, _prev_r} ->
          {n, r} = Zoom.decompose(z, prev_n)
          assert n >= prev_n
          assert r >= @r_min - 1.0e-9
          assert r <= @r_max + 1.0e-9
          {n, r}
        end)
    end

    test "sweep back 11→0.7: n non-increasing, r in range" do
      z_values = for i <- 0..188, do: 11.0 - i * 0.05

      {_n, _r} =
        Enum.reduce(z_values, {3, 1.0}, fn z, {prev_n, _prev_r} ->
          {n, r} = Zoom.decompose(z, prev_n)
          assert n <= prev_n
          assert r >= @r_min - 1.0e-9
          assert r <= @r_max + 1.0e-9
          {n, r}
        end)
    end

    test "hysteresis: oscillate 2.7↔2.9 from n=1 keeps n=1; z=3.1 → n=2" do
      n = 1

      n =
        Enum.reduce([2.7, 2.9, 2.7, 2.9, 2.7, 2.9], n, fn z, acc_n ->
          {next_n, _r} = Zoom.decompose(z, acc_n)
          assert next_n == 1
          next_n
        end)

      {n, _r} = Zoom.decompose(3.1, n)
      assert n == 2
    end

    test "z < 1 uses n = 0" do
      assert Zoom.decompose(0.7, 0) == {0, 0.7}
    end

    test "octave boundaries" do
      assert Zoom.decompose(2.0, 0) == {1, 1.0}
      assert Zoom.decompose(4.0, 1) == {2, 1.0}
      assert Zoom.decompose(8.0, 2) == {3, 1.0}
    end
  end

  describe "mobius_sigma/1" do
    test "neutral at r=1" do
      assert Zoom.mobius_sigma(1.0) == 0.0
    end

    test "non-zero for r != 1" do
      refute Zoom.mobius_sigma(1.2) == 0.0
    end
  end

  describe "apply_chart_octave/4" do
    test "anchors at pivot" do
      x_p = 10.0
      assert Zoom.apply_chart_octave(10.0, 3.0, 2.0, x_p) == {10.0, 6.0}
      assert Zoom.apply_chart_octave(14.0, 3.0, 2.0, x_p) == {18.0, 6.0}
    end
  end

  describe "Möbius orientation (gates wiring)" do
    test "sigma = log(r) makes pattern denser at pivot for r > 1" do
      w = 312
      alpha = Sphere.alpha(w)
      cx = w / 2 - 0.5
      pivot_x = 50.0
      phi_a = (pivot_x - cx) * alpha
      basis = Sphere.mobius_basis(phi_a)
      {_u, _v, a} = basis

      eps = 0.02
      {ax, ay, az} = a
      d0 = normalize({ax + eps, ay, az})
      d1 = normalize({ax, ay + eps, az})

      test_r = 2.0
      sigma_pos = :math.log(test_r)
      sigma_neg = -:math.log(test_r)

      ratio_for = fn sigma ->
        o0 = Sphere.dilate(d0, sigma, basis)
        o1 = Sphere.dilate(d1, sigma, basis)
        {x0, y0} = Sphere.to_chart(o0, alpha)
        {x1, y1} = Sphere.to_chart(o1, alpha)
        dist = :math.sqrt((x1 - x0) * (x1 - x0) + (y1 - y0) * (y1 - y0))
        {x0b, y0b} = Sphere.to_chart(d0, alpha) |> then(fn {x, y} -> {x, y} end)
        {x1b, y1b} = Sphere.to_chart(d1, alpha) |> then(fn {x, y} -> {x, y} end)
        base = :math.sqrt((x1b - x0b) * (x1b - x0b) + (y1b - y0b) * (y1b - y0b))
        dist / base
      end

      ratio_pos = ratio_for.(sigma_pos)
      ratio_neg = ratio_for.(sigma_neg)

      assert ratio_pos > 1.0
      assert ratio_neg < 1.0
      assert Zoom.mobius_residual_sign() == 1
    end
  end

  describe "advance_octave_state/3" do
    test "starts fade on octave change" do
      state = %{zoom_octave_n: 0, octave_fade: nil}
      now = 100.0

      {updates, committed_n, fade} = Zoom.advance_octave_state(state, 2.0, now)

      assert committed_n == 0
      assert fade == %{from_n: 0, to_n: 1, started_at: now}
      assert updates == %{octave_fade: fade}
    end

    test "completes fade when u reaches 1" do
      state = %{
        zoom_octave_n: 0,
        octave_fade: %{from_n: 0, to_n: 1, started_at: 100.0}
      }

      now = 100.0 + Zoom.octave_fade_dur()

      {updates, committed_n, fade} = Zoom.advance_octave_state(state, 2.0, now)

      assert committed_n == 1
      assert fade == nil
      assert updates == %{zoom_octave_n: 1, octave_fade: nil}
    end

    test "mid-fade switch restarts from old to_n" do
      state = %{
        zoom_octave_n: 0,
        octave_fade: %{from_n: 0, to_n: 1, started_at: 100.0}
      }

      now = 100.5

      {updates, committed_n, fade} = Zoom.advance_octave_state(state, 4.0, now)

      assert committed_n == 0
      assert fade == %{from_n: 1, to_n: 2, started_at: now}
      assert updates == %{octave_fade: fade}
    end
  end

  defp normalize({x, y, z}) do
    n = :math.sqrt(x * x + y * y + z * z)
    {x / n, y / n, z / n}
  end
end
