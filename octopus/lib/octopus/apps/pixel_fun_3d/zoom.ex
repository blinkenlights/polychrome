defmodule Octopus.Apps.PixelFun3D.Zoom do
  @moduledoc """
  Combined zoom: integer octave chart scaling (seam-free densification) plus
  bounded Möbius residual magnification at the pivot.

  Any zoom factor `z` decomposes as `z = m * r` where `m = 2^n` (n ∈ 0..3)
  and `r ∈ [1/√2, √2)` under steady-state rounding; hysteresis may push r
  slightly past √2 harmlessly.
  """

  alias Octopus.Sphere

  @mobius_neutral_eps 1.0e-9
  @octave_fade_dur 1.5
  @hysteresis_margin 0.55
  @min_n 0
  @max_n 3

  # Verified by orientation test in zoom_test.exs — sigma = @mobius_residual_sign * log(r).
  @mobius_residual_sign 1

  @doc false
  def octave_fade_dur, do: @octave_fade_dur

  @doc """
  Decompose zoom factor `z` into octave index `n` and Möbius residual `r`.

  Hysteresis around octave boundaries uses `current_n` to prevent ping-pong
  when the auto-wanderer oscillates near `2^k`.
  """
  @spec decompose(float(), integer()) :: {integer(), float()}
  def decompose(z, current_n) when is_number(z) and is_integer(current_n) do
    current_n = current_n |> max(@min_n) |> min(@max_n)
    n = base_n(z)
    n = apply_hysteresis(z, current_n, n)
    r = z / octave_factor(n)
    {n, r}
  end

  @doc "Octave multiplier `m = 2^n`."
  @spec octave_factor(integer()) :: float()
  def octave_factor(n) when is_integer(n), do: :math.pow(2, n)

  @doc """
  Möbius log-scale for residual `r`. Returns `0` when `r ≈ 1` (identity skip).
  """
  @spec mobius_sigma(float()) :: float()
  def mobius_sigma(r) when is_number(r) do
    if abs(r - 1.0) < @mobius_neutral_eps do
      0.0
    else
      @mobius_residual_sign * :math.log(r)
    end
  end

  @doc """
  Pivot-anchored chart octave scaling.

  `m` must be a power-of-two integer so a W-periodic pattern in `x_s` stays
  W-periodic after scaling (shift by `m·W` is still an integer multiple of
  the period). Anchoring at `x_p` keeps density and phase continuous at the
  zoom pivot during octave crossfades.
  """
  @spec apply_chart_octave(float(), float(), float(), float()) :: {float(), float()}
  def apply_chart_octave(xs, ys, m, x_p) when is_number(xs) and is_number(ys) and is_number(m) and is_number(x_p) do
    {x_p + m * (xs - x_p), m * ys}
  end

  @doc false
  def mobius_residual_sign, do: @mobius_residual_sign

  @doc """
  Smoothstep blend factor `u ∈ [0, 1]` for an active octave fade, or `nil`.
  """
  @spec fade_u(nil | map(), float()) :: nil | float()
  def fade_u(nil, _now), do: nil

  def fade_u(%{started_at: started_at}, now) when is_number(started_at) and is_number(now) do
    p = (now - started_at) / @octave_fade_dur |> clamp(0.0, 1.0)
    if p >= 1.0, do: 1.0, else: p * p * (3.0 - 2.0 * p)
  end

  @doc """
  Advance runtime octave state from live zoom `z` and wall-clock `now`.

  Returns `{state_map, committed_n, fade_map}` where `state_map` holds
  `:zoom_octave_n` and `:octave_fade` updates.
  """
  @spec advance_octave_state(map(), float(), float()) :: {map(), integer(), nil | map()}
  def advance_octave_state(state, z, now) do
    current_n = Map.get(state, :zoom_octave_n, 0) || 0
    fade = Map.get(state, :octave_fade)
    {target_n, _r} = decompose(z, current_n)

    fade =
      cond do
        fade == nil and target_n != current_n ->
          %{from_n: current_n, to_n: target_n, started_at: now}

        fade != nil and target_n != fade.to_n ->
          %{from_n: fade.to_n, to_n: target_n, started_at: now}

        true ->
          fade
      end

    u = fade_u(fade, now)

    if fade != nil and u == 1.0 do
      {%{zoom_octave_n: fade.to_n, octave_fade: nil}, fade.to_n, nil}
    else
      # zoom_octave_n commits only when the fade finishes; hysteresis uses it meanwhile.
      {%{octave_fade: fade}, current_n, fade}
    end
  end

  @doc """
  Full per-pixel sample with octave chart multiplier and Möbius residual.

  Returns `{xs', ys', direction}` where direction is post-Möbius (for nx/ny/nz).
  """
  @spec sample_pixel(Sphere.vec3(), map(), float(), float(), float()) ::
          {float(), float(), Sphere.vec3()}
  def sample_pixel(d, params, m, r, x_p) do
    %{
      matrix: matrix,
      mobius_basis: basis,
      elev_rad: elev_rad,
      alpha: alpha
    } = params

    sigma = mobius_sigma(r)

    d =
      d
      |> then(&Sphere.transform(matrix, &1))
      |> Sphere.dilate(sigma, basis)
      |> Sphere.apply_elevation(elev_rad, alpha)

    {xs, ys} = Sphere.to_chart(d, alpha)
    apply_chart_octave(xs, ys, m, x_p) |> then(fn {xs, ys} -> {xs, ys, d} end)
  end

  defp base_n(z) when z < 1.0, do: 0

  defp base_n(z) do
    z |> :math.log2() |> round() |> max(@min_n) |> min(@max_n)
  end

  defp apply_hysteresis(z, current_n, candidate_n) do
    up_threshold = :math.pow(2, current_n + @hysteresis_margin)
    down_threshold = :math.pow(2, current_n - @hysteresis_margin)

    cond do
      candidate_n > current_n and z <= up_threshold -> current_n
      candidate_n < current_n and z >= down_threshold -> current_n
      true -> candidate_n
    end
    |> max(@min_n)
    |> min(@max_n)
  end

  defp clamp(v, lo, _hi) when v < lo, do: lo
  defp clamp(v, _lo, hi) when v > hi, do: hi
  defp clamp(v, _lo, _hi), do: v
end
