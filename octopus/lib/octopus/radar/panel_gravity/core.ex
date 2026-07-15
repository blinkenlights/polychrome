defmodule Octopus.Radar.PanelGravity.Core do
  @moduledoc false

  alias Octopus.Radar.PanelGravity.Settings

  # Reference ring radius used to calibrate reach: one object at the centre
  # with reach=100 yields ~0.5 gravity on every panel of a 10 m Nation ring.
  @ref_radius_m 10.0

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
  Sums per-object gravity into installation panel numbers (1-based).

  For every panel and every object: evaluate exponential falloff of distance,
  then sum. No cross-panel normalisation happens here.
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
  Absolute panel gravity in 0..1.

  Maps the summed raw value of each panel independently — never min–max across
  the ring (that would turn a centred object into uneven bright/dark panels).
  """
  @spec targets(panel_map(), float(), Settings.t()) :: panel_map()
  def targets(raw, _ref, %Settings{sensitivity: sensitivity, contrast: contrast}) do
    Map.new(raw, fn {panel, value} ->
      level = (sensitivity * value) |> max(0.0) |> min(1.0)
      # Contrast as gamma on absolute brightness (1 = identity-ish mid, higher = darker mids).
      level = :math.pow(level, max(contrast, 0.01) / 3.0)
      {panel, clamp01(level)}
    end)
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

  @doc """
  Single object → panel gravity.

  Exponential falloff of softened distance. Reach 1..100 raises both the
  characteristic length (shallower decay) and amplitude (overall stronger),
  so a high reach yields higher per-panel sums.
  """
  @spec contribution(person(), panel_pos(), Settings.t()) :: float()
  def contribution(%{x: x, y: y}, %{x: px, y: py}, %Settings{} = settings) do
    dx = x - px
    dy = y - py
    d = :math.sqrt(dx * dx + dy * dy)
    soft = max(settings.softening_m, 0.0)
    d_soft = :math.sqrt(d * d + soft * soft)

    {lambda, amplitude} = reach_params(settings.reach)
    settings.mass * amplitude * :math.exp(-d_soft / lambda)
  end

  # t=0 (reach 1): short λ, low amplitude → distant objects almost irrelevant.
  # t=1 (reach 100): λ ≈ R/ln(2) so an object at the ring centre is ~0.5.
  #
  # Interpolating on sqrt(t) rather than t bends the curve concave: reach
  # already hits hard by the middle of the range instead of only paying off
  # near 100, while both endpoints (and their calibration) stay unchanged.
  defp reach_params(reach) do
    t = :math.sqrt((clamp_reach(reach) - 1) / 99.0)
    lambda_min = 0.6
    lambda_max = @ref_radius_m / :math.log(2)
    lambda = lambda_min + (lambda_max - lambda_min) * t

    amp_min = 0.2
    amp_max = 1.0
    amplitude = amp_min + (amp_max - amp_min) * t

    {lambda, amplitude}
  end

  defp clamp_reach(reach) when is_number(reach), do: reach |> max(1) |> min(100)
  defp clamp_reach(_), do: 50

  defp clamp01(v), do: v |> max(0.0) |> min(1.0)
end
