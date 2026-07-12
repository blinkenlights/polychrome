defmodule Octopus.Wander do
  @moduledoc """
  Stochastic segment wanderer: eases from the current value toward a random
  target over an interval-scaled duration.

  Values are N-tuples of floats. A scalar is a 1-tuple; `new/1` accepts a
  float or a tuple. One segment shares duration and easing across all
  dimensions — motion is diagonal, not axis-staggered.

  Uses the process default `:rand` RNG. Determinism is **not** required —
  two runs of the same preset may differ.
  """

  @easings [:smoothstep, :sine_in_out, :cubic_in_out]

  defstruct [:value, :seg_from, :target, :seg_start, :seg_dur, :easing]

  @type vec :: tuple()
  @type t :: %__MODULE__{
          value: vec(),
          seg_from: vec(),
          target: vec(),
          seg_start: float() | :pending,
          seg_dur: float(),
          easing: atom()
        }

  @spec new(number() | tuple()) :: t()
  def new(initial) when is_number(initial), do: new({initial * 1.0})

  def new(initial) when is_tuple(initial) and tuple_size(initial) >= 1 do
    v = map_vec(initial, &(&1 * 1.0))

    %__MODULE__{
      value: v,
      seg_from: v,
      target: v,
      seg_start: :pending,
      seg_dur: 0.0,
      easing: :smoothstep
    }
  end

  @doc """
  Step a wanderer. Scalar opts: `%{min:, max:, interval:}`. Vector opts: `%{mins:, maxs:, interval:}`.
  """
  def step(%__MODULE__{} = w, now, %{min: min, max: max, interval: interval})
      when is_number(now) and is_number(min) and is_number(max) and is_number(interval) and
             tuple_size(w.value) == 1 do
    {value, next} =
      step_vec(w, now, %{mins: {min * 1.0}, maxs: {max * 1.0}, interval: interval * 1.0})

    {elem(value, 0), next}
  end

  def step(%__MODULE__{} = w, now, %{mins: mins, maxs: maxs, interval: interval})
      when is_number(now) and is_tuple(mins) and is_tuple(maxs) and is_number(interval) do
    step_vec(w, now, %{mins: mins, maxs: maxs, interval: interval * 1.0})
  end

  defp step_vec(%__MODULE__{} = w, now, %{mins: mins, maxs: maxs, interval: interval}) do
    n = tuple_size(w.value)
    true = tuple_size(mins) == n and tuple_size(maxs) == n

    bounds =
      for i <- 0..(n - 1) do
        ordered(elem(mins, i), elem(maxs, i))
      end
      |> List.to_tuple()

    if interval <= 0.0 do
      held = clamp_vec(w.value, bounds)
      {held, %{w | value: held, seg_start: :pending}}
    else
      w = ensure_in_range(w, now, bounds, interval)

      case w.seg_start do
        :pending ->
          next = roll_segment(w, now, bounds, interval)
          {clamp_vec(next.value, bounds), next}

        _ ->
          w = maybe_retarget_for_range(w, now, bounds, interval)
          p = clamp_scalar((now - w.seg_start) / max(w.seg_dur, 1.0e-9), 0.0, 1.0)
          e = ease(w.easing, p)

          value =
            for i <- 0..(n - 1) do
              elem(w.seg_from, i) + (elem(w.target, i) - elem(w.seg_from, i)) * e
            end
            |> List.to_tuple()

          if p >= 1.0 do
            finalized = %{w | value: clamp_vec(w.target, bounds)}
            next = roll_segment(finalized, now, bounds, interval)
            {finalized.value, next}
          else
            value = clamp_vec(value, bounds)
            {value, %{w | value: value}}
          end
      end
    end
  end

  @doc false
  def ease(:smoothstep, p) do
    p = clamp_scalar(p, 0.0, 1.0)
    p * p * (3.0 - 2.0 * p)
  end

  def ease(:sine_in_out, p) do
    p = clamp_scalar(p, 0.0, 1.0)
    (1.0 - :math.cos(:math.pi() * p)) / 2.0
  end

  def ease(:cubic_in_out, p) do
    p = clamp_scalar(p, 0.0, 1.0)

    if p < 0.5 do
      4.0 * p * p * p
    else
      1.0 - :math.pow(-2.0 * p + 2.0, 3) / 2.0
    end
  end

  defp ensure_in_range(%__MODULE__{} = w, now, bounds, interval) do
    if out_of_bounds?(w.value, bounds) do
      clamped = clamp_vec(w.value, bounds)
      roll_segment(%{w | value: clamped, seg_from: clamped}, now, bounds, interval)
    else
      w
    end
  end

  defp maybe_retarget_for_range(%__MODULE__{} = w, now, bounds, interval) do
    if out_of_bounds?(w.target, bounds) do
      roll_segment(%{w | seg_from: w.value, value: w.value}, now, bounds, interval)
    else
      w
    end
  end

  defp roll_segment(%__MODULE__{} = w, now, bounds, interval) do
    n = tuple_size(w.value)

    target =
      for i <- 0..(n - 1) do
        {lo, hi} = elem(bounds, i)
        lo + :rand.uniform() * (hi - lo)
      end
      |> List.to_tuple()

    jitter = 0.7 + :rand.uniform() * 0.7
    seg_dur = interval * jitter
    easing = Enum.at(@easings, :rand.uniform(length(@easings)) - 1)

    %{
      w
      | seg_from: w.value,
        target: target,
        seg_start: now,
        seg_dur: seg_dur,
        easing: easing,
        value: w.value
    }
  end

  defp out_of_bounds?(vec, bounds) do
    Enum.any?(0..(tuple_size(vec) - 1), fn i ->
      v = elem(vec, i)
      {lo, hi} = elem(bounds, i)
      v < lo or v > hi
    end)
  end

  defp clamp_vec(vec, bounds) do
    for i <- 0..(tuple_size(vec) - 1) do
      {lo, hi} = elem(bounds, i)
      clamp_scalar(elem(vec, i), lo, hi)
    end
    |> List.to_tuple()
  end

  defp map_vec(vec, fun) do
    Enum.map(0..(tuple_size(vec) - 1), fn i -> fun.(elem(vec, i)) end)
    |> List.to_tuple()
  end

  defp ordered(a, b) when a <= b, do: {a * 1.0, b * 1.0}
  defp ordered(a, b), do: {b * 1.0, a * 1.0}

  defp clamp_scalar(v, lo, _hi) when v < lo, do: lo
  defp clamp_scalar(v, _lo, hi) when v > hi, do: hi
  defp clamp_scalar(v, _lo, _hi), do: v
end
