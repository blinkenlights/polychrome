defmodule Octopus.Radar.PanelActivity.Core do
  @moduledoc false

  alias Octopus.Radar.PanelActivity.Settings
  alias Octopus.Radar.PanelMapping

  @type person :: %{
          required(:id) => pos_integer(),
          required(:x) => float(),
          required(:y) => float(),
          optional(:vx) => float(),
          optional(:vy) => float()
        }

  @type panel_map :: %{pos_integer() => float()}

  @doc """
  Sums per-person contributions into frame-panel indices (0-based).
  """
  @spec raw_factors([person()], pos_integer(), float(), Settings.t()) :: panel_map()
  def raw_factors(people, num_panels, ring_outer, %Settings{} = settings) do
    base = for p <- 0..(num_panels - 1), into: %{}, do: {p, 0.0}

    Enum.reduce(people, base, fn person, acc ->
      r = PanelMapping.track_radius(person)
      w_radius = radius_weight(r, ring_outer, settings.radius_weight_max)
      w_walk = walk_multiplier(PanelMapping.track_speed(person), settings.walk_threshold)

      panel =
        person
        |> PanelMapping.sim_panel_3d(num_panels)
        |> PanelMapping.frame_panel_of_3d(num_panels)

      contrib = w_radius * w_walk
      Map.update(acc, panel, contrib, &(&1 + contrib))
    end)
  end

  @doc """
  Slow auto-gain reference. Non-adaptive mode holds a fixed floor reference.
  """
  @spec update_ref(float(), panel_map(), boolean(), float(), Settings.t()) :: float()
  def update_ref(_ref, _raw, false, _dt, %Settings{min_ref: min_ref}), do: min_ref

  def update_ref(ref, raw, true, dt, %Settings{min_ref: min_ref, ref_tau: ref_tau}) do
    cur_max = raw |> Map.values() |> Enum.max(fn -> 0.0 end)
    target = max(cur_max, min_ref)
    alpha = 1.0 - :math.exp(-dt / ref_tau)
    ref + (target - ref) * alpha
  end

  @doc """
  Normalised pre-EMA targets in 0..1 (frame-panel indices).
  """
  @spec targets(panel_map(), float(), Settings.t()) :: panel_map()
  def targets(raw, ref, %Settings{sensitivity: sensitivity}) when ref > 0.0 do
    Map.new(raw, fn {panel, value} ->
      {panel, soft(sensitivity * value / ref)}
    end)
  end

  def targets(raw, _ref, _settings), do: Map.new(raw, fn {panel, _} -> {panel, 0.0} end)

  @doc """
  Asymmetric per-panel EMA: fast attack, slow release (frame-panel indices).
  """
  @spec smooth_asymmetric(panel_map(), panel_map(), float(), Settings.t()) :: panel_map()
  def smooth_asymmetric(level, target, dt, %Settings{} = settings) do
    Map.merge(level, target, fn _panel, cur, tgt ->
      tau = if tgt > cur, do: settings.attack_tau, else: settings.release_tau
      alpha = 1.0 - :math.exp(-dt / tau)
      cur + (tgt - cur) * alpha
    end)
  end

  @doc """
  Converts frame-panel indices (0-based) to physical installation panel numbers
  (1-based), honouring `:north_panel`.
  """
  @spec to_installation_panels(panel_map(), pos_integer(), pos_integer()) :: panel_map()
  def to_installation_panels(map, num_panels, north_panel) do
    Map.new(map, fn {frame_panel, value} ->
      {PanelMapping.installation_panel_of_frame(frame_panel, num_panels, north_panel), value}
    end)
    |> ensure_all_panels(num_panels)
  end

  @doc """
  Empty installation-panel map (1..N) with zero values.
  """
  @spec empty_installation_panels(pos_integer()) :: panel_map()
  def empty_installation_panels(num_panels) do
    for p <- 1..num_panels, into: %{}, do: {p, 0.0}
  end

  defp ensure_all_panels(map, num_panels) do
    Enum.reduce(1..num_panels, map, fn panel, acc ->
      Map.put_new(acc, panel, 0.0)
    end)
  end

  defp radius_weight(r, ring_outer, max_weight) when ring_outer > 0.0 do
    1.0 + (max_weight - 1.0) * clamp01(r / ring_outer)
  end

  defp radius_weight(_r, _ring_outer, _max_weight), do: 1.0

  defp walk_multiplier(speed, threshold) when speed > threshold, do: 2.0
  defp walk_multiplier(_speed, _threshold), do: 1.0

  defp soft(x) when x <= 0.0, do: 0.0
  defp soft(x), do: x / (1.0 + x)

  defp clamp01(v), do: v |> max(0.0) |> min(1.0)
end
