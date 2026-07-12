defmodule Octopus.Wander do
  @moduledoc """
  Stochastic segment wanderer: eases from the current value toward a random
  target in `[min, max]` over a tempo-scaled duration.

  Uses the process default `:rand` RNG. Determinism is **not** required —
  two runs of the same preset may differ.
  """

  @base_dur 12.0
  @easings [:smoothstep, :sine_in_out, :cubic_in_out]

  defstruct [:value, :seg_from, :target, :seg_start, :seg_dur, :easing]

  @type t :: %__MODULE__{
          value: float(),
          seg_from: float(),
          target: float(),
          seg_start: float() | :pending,
          seg_dur: float(),
          easing: atom()
        }

  @spec new(float()) :: t()
  def new(initial) when is_number(initial) do
    v = initial * 1.0

    %__MODULE__{
      value: v,
      seg_from: v,
      target: v,
      seg_start: :pending,
      seg_dur: 0.0,
      easing: :smoothstep
    }
  end

  @spec step(t(), float(), %{min: float(), max: float(), tempo: float()}) :: {float(), t()}
  def step(%__MODULE__{} = w, now, %{min: min, max: max, tempo: tempo})
      when is_number(now) and is_number(min) and is_number(max) and is_number(tempo) do
    {lo, hi} = ordered(min, max)

    if tempo == 0.0 do
      held = clamp(w.value, lo, hi)
      {held, %{w | value: held, seg_start: :pending}}
    else
      w = ensure_in_range(w, now, lo, hi, tempo)

      case w.seg_start do
        :pending ->
          next = roll_segment(w, now, lo, hi, tempo)
          {clamp(next.value, lo, hi), next}

        _ ->
          w = maybe_retarget_for_range(w, now, lo, hi, tempo)
          p = clamp((now - w.seg_start) / max(w.seg_dur, 1.0e-9), 0.0, 1.0)
          value = w.seg_from + (w.target - w.seg_from) * ease(w.easing, p)

          if p >= 1.0 do
            finalized = %{w | value: clamp(w.target, lo, hi)}
            next = roll_segment(finalized, now, lo, hi, tempo)
            {finalized.value, next}
          else
            value = clamp(value, lo, hi)
            {value, %{w | value: value}}
          end
      end
    end
  end

  @doc false
  def ease(:smoothstep, p) do
    p = clamp(p, 0.0, 1.0)
    p * p * (3.0 - 2.0 * p)
  end

  def ease(:sine_in_out, p) do
    p = clamp(p, 0.0, 1.0)
    (1.0 - :math.cos(:math.pi() * p)) / 2.0
  end

  def ease(:cubic_in_out, p) do
    p = clamp(p, 0.0, 1.0)

    if p < 0.5 do
      4.0 * p * p * p
    else
      1.0 - :math.pow(-2.0 * p + 2.0, 3) / 2.0
    end
  end

  defp ensure_in_range(%__MODULE__{} = w, now, lo, hi, tempo) do
    if w.value < lo or w.value > hi do
      clamped = clamp(w.value, lo, hi)
      roll_segment(%{w | value: clamped, seg_from: clamped}, now, lo, hi, tempo)
    else
      w
    end
  end

  defp maybe_retarget_for_range(%__MODULE__{} = w, now, lo, hi, tempo) do
    if w.target < lo or w.target > hi do
      roll_segment(%{w | seg_from: w.value, value: w.value}, now, lo, hi, tempo)
    else
      w
    end
  end

  defp roll_segment(%__MODULE__{} = w, now, lo, hi, tempo) do
    target = lo + :rand.uniform() * (hi - lo)
    jitter = 0.7 + :rand.uniform() * 0.7
    seg_dur = @base_dur / max(tempo, 0.05) * jitter
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

  defp ordered(a, b) when a <= b, do: {a * 1.0, b * 1.0}
  defp ordered(a, b), do: {b * 1.0, a * 1.0}

  defp clamp(v, lo, _hi) when v < lo, do: lo
  defp clamp(v, _lo, hi) when v > hi, do: hi
  defp clamp(v, _lo, _hi), do: v
end
