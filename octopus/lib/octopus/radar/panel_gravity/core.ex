defmodule Octopus.Radar.PanelGravity.Core do
  @moduledoc false

  alias Octopus.Radar.PanelGravity.Settings

  @type person :: %{
          required(:id) => pos_integer(),
          required(:x) => float(),
          required(:y) => float(),
          optional(:vx) => float(),
          optional(:vy) => float()
        }

  @type panel_map :: %{pos_integer() => float()}

  @type panel_pos :: %{
          required(:panel) => pos_integer(),
          required(:x) => float(),
          required(:y) => float()
        }

  @doc """
  Sums per-object gravitational contributions into installation panel numbers
  (1-based).
  """
  @spec raw_gravity([person()], [panel_pos()], Settings.t()) :: panel_map()
  def raw_gravity(people, panel_positions, %Settings{} = settings) do
    base = empty_panels(panel_positions)

    Enum.reduce(people, base, fn person, acc ->
      Enum.reduce(panel_positions, acc, fn panel_pos, acc2 ->
        contrib = contribution(person, panel_pos, settings)
        Map.update!(acc2, panel_pos.panel, &(&1 + contrib))
      end)
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
  Normalised pre-EMA targets in 0..1 (installation panel numbers).

  Peak panel is scaled to 1.0; others follow `(value / max)^contrast` so
  nearby panels stay bright while distant ones fall off sharply. When all
  panels are effectively equal (no proximity signal), every target is 0.
  """
  @spec targets(panel_map(), float(), Settings.t()) :: panel_map()
  def targets(raw, _ref, %Settings{sensitivity: sensitivity, min_ref: min_span, contrast: contrast}) do
    values = Map.values(raw)
    min_v = Enum.min(values, fn -> 0.0 end)
    max_v = Enum.max(values, fn -> 0.0 end)
    span = max_v - min_v

    if max_v <= 0.0 or span < min_span do
      Map.new(raw, fn {panel, _} -> {panel, 0.0} end)
    else
      Map.new(raw, fn {panel, value} ->
        ratio = value / max_v
        normalized = sensitivity * :math.pow(ratio, contrast)
        {panel, normalized |> max(0.0) |> min(1.0)}
      end)
    end
  end

  @doc """
  Asymmetric per-panel EMA: fast attack, slow release.
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
  Empty installation-panel map (1..N) with zero values.
  """
  @spec empty_installation_panels(pos_integer()) :: panel_map()
  def empty_installation_panels(num_panels) do
    for p <- 1..num_panels, into: %{}, do: {p, 0.0}
  end

  @spec empty_panels([panel_pos()]) :: panel_map()
  def empty_panels(panel_positions) do
    Map.new(panel_positions, fn %{panel: panel} -> {panel, 0.0} end)
  end

  @spec contribution(person(), panel_pos(), Settings.t()) :: float()
  def contribution(%{x: x, y: y}, %{x: px, y: py}, %Settings{} = settings) do
    dx = x - px
    dy = y - py
    d = :math.sqrt(dx * dx + dy * dy)
    softening_pow = :math.pow(settings.softening_m, settings.exponent)
    denom = :math.pow(d, settings.exponent) + softening_pow
    settings.mass / denom
  end

end
