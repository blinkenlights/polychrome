defmodule Octopus.Apps.Collective.CrowdActivity do
  @moduledoc """
  Shared per-panel crowd activity factor for Collective animations.

  Activity factor per panel = Σ over people mapped to that panel of
  `radius_weight * walk_multiplier`:

    * radius weight — near the mast (centre) counts 1, near the panels (ring
      outer) counts up to 3 (linear in `r / ring_radius`).
    * walk multiplier — moving faster than a small threshold counts double.

  `update_ref/4` provides a slow auto-gain reference (running panel max, floored)
  so the factor can be normalised to the current crowd; `soft/1` soft-compresses
  the normalised value into `0..1` without hard-clipping.

  Extracted from `PresencePanels` so `LavaLamp` (and future animations) share the
  exact same crowd signal.
  """

  alias Octopus.Radar.PanelMapping

  # m/s over which a person is considered "walking" (counts double).
  @walk_threshold 0.35
  # Floor for the auto-gain reference so an empty ring doesn't amplify noise.
  @min_ref 4.0
  # Time constant (s) for the slow auto-gain reference.
  @ref_tau 8.0

  @doc "Walking speed threshold (m/s) above which a person counts double."
  def walk_threshold, do: @walk_threshold

  @doc "Floor for the auto-gain reference (also the fixed reference in non-adaptive mode)."
  def min_ref, do: @min_ref

  @doc """
  Raw activity factor per frame panel index (0..num_panels-1).
  """
  def raw_factors(people, num_panels, ring_outer) do
    base = for p <- 0..(num_panels - 1), into: %{}, do: {p, 0.0}

    Enum.reduce(people, base, fn person, acc ->
      r = PanelMapping.track_radius(person)
      w_radius = 1.0 + 2.0 * clamp01(r / ring_outer)
      w_walk = if PanelMapping.track_speed(person) > @walk_threshold, do: 2.0, else: 1.0

      panel =
        person
        |> PanelMapping.sim_panel_3d(num_panels)
        |> PanelMapping.frame_panel_of_3d(num_panels)

      Map.update(acc, panel, w_radius * w_walk, &(&1 + w_radius * w_walk))
    end)
  end

  @doc """
  Slow auto-gain: track the running panel max, floored. Non-adaptive mode holds a
  fixed reference so the factor reads as an absolute intensity.
  """
  def update_ref(_ref, _raw, false, _dt), do: @min_ref

  def update_ref(ref, raw, true, dt) do
    cur_max = raw |> Map.values() |> Enum.max(fn -> 0.0 end)
    target = max(cur_max, @min_ref)
    alpha = 1.0 - :math.exp(-dt / @ref_tau)
    ref + (target - ref) * alpha
  end

  @doc "x/(1+x): 0->0, saturates smoothly toward 1, never hard-clips."
  def soft(x) when x <= 0.0, do: 0.0
  def soft(x), do: x / (1.0 + x)

  defp clamp01(v), do: v |> max(0.0) |> min(1.0)
end
