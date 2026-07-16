defmodule Octopus.Apps.GravityMask do
  @moduledoc """
  Greyscale proximity mask driven by per-panel gravity from radar tracks.

  Subscribes to `Octopus.Radar.PanelGravity` and maps normalised gravity
  factors to panel brightness. Renders only when the gravity snapshot or
  local display config changes — no per-tick GenServer polling.
  """

  use Octopus.App, category: :animation, output_type: :grayscale

  @mode_presets Module.concat(["Octopus", "AppModePresets"])

  require Logger

  alias Octopus.Canvas
  alias Octopus.Installation
  alias Octopus.Radar

  @panel_width 8
  @default_easing_tau 1.5
  @debug_log_interval_ms 1_000

  def name, do: "Gravity Mask"

  def compatible? do
    Installation.arrangement() == :circular and Radar.configured?()
  end

  def list_modes do
    apply(@mode_presets, :list_modes, [__MODULE__])
  end

  def mode_config(mode_id) do
    apply(@mode_presets, :config_for, [__MODULE__, mode_id]) || default_config()
  end

  defp default_config do
    %{easing_tau: @default_easing_tau}
  end

  def mode_tweakables(mode_id) do
    mode_tweakables_for(apply(@mode_presets, :mode_slug, [mode_id]))
  end

  def mode_tweakables_for(slug) when slug in ["mask", "default"] do
    [
      %{
        key: :easing_tau,
        label: "Easing",
        type: :slider,
        min: 0.0,
        max: 5.0,
        step: 0.1,
        unit: "s",
        default: @default_easing_tau
      }
    ]
  end

  def mode_tweakables_for(_), do: []

  def now_playing_meta(config) do
    easing = Map.get(config, :easing_tau, @default_easing_tau)
    ["easing #{easing}s"]
  end

  def app_init(config) do
    Octopus.App.configure_display(
      layout: :adjacent_panels,
      supports_rgb: false,
      supports_grayscale: true,
      easing_interval: 0
    )

    display_info = Octopus.App.get_display_info()

    if Process.whereis(Octopus.Radar.PanelGravity) do
      :ok = Radar.subscribe_panel_gravity()
    end

    apply_gravity_config(config)

    state = %{
      display_info: display_info,
      factors: %{},
      rendered_levels: nil,
      easing_tau: Map.get(config, :easing_tau, @default_easing_tau),
      last_debug_ms: nil
    }

    # One-shot initial paint from current snapshot (no polling loop).
    send(self(), :paint_now)

    Logger.debug(
      "[GravityMask] started easing_tau=#{Map.get(config, :easing_tau, @default_easing_tau)}s " <>
        "panel_gravity=#{inspect(Process.whereis(Octopus.Radar.PanelGravity) != nil)}"
    )

    {:ok, state}
  end

  def handle_info(:paint_now, state) do
    factors =
      if Process.whereis(Octopus.Radar.PanelGravity) do
        Radar.panel_gravity() |> factors_from_snapshot(state.factors)
      else
        state.factors
      end

    {:noreply, maybe_render(%{state | factors: factors}, force: true)}
  end

  def handle_info({:panel_gravity, snapshot}, state) when is_map(snapshot) do
    factors = factors_from_snapshot(snapshot, state.factors)
    now = :erlang.monotonic_time(:millisecond)

    state =
      if debug_due?(now, state.last_debug_ms) do
        levels = levels_from_factors(factors, state.display_info)
        log_display_debug(%{state | factors: factors}, factors, levels)
        %{state | last_debug_ms: now}
      else
        state
      end

    {:noreply, maybe_render(%{state | factors: factors})}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  def config_schema do
    %{
      easing_tau: {"Easing", :float, %{min: 0.0, max: 5.0, step: 0.1, default: @default_easing_tau}}
    }
  end

  def get_config(state) do
    %{easing_tau: state.easing_tau}
  end

  def handle_config(config, state) do
    apply_gravity_config(config)
    state = %{state | easing_tau: Map.get(config, :easing_tau, state.easing_tau)}
    {:noreply, maybe_render(state, force: true)}
  end

  defp factors_from_snapshot(snapshot, fallback) do
    case snapshot do
      %{gravity: gravity} when map_size(gravity) > 0 -> gravity
      %{target: target} when map_size(target) > 0 -> target
      _ -> fallback
    end
  end

  defp maybe_render(state, opts \\ []) do
    force? = Keyword.get(opts, :force, false)
    levels = levels_from_factors(state.factors, state.display_info)

    if force? or levels != state.rendered_levels do
      canvas = render_canvas(state, levels)
      Octopus.App.update_display(canvas, :grayscale)
      %{state | rendered_levels: levels}
    else
      state
    end
  end

  defp levels_from_factors(factors, display_info) do
    num_panels = max(div(display_info.width, @panel_width), 1)

    for panel <- 1..num_panels, into: %{} do
      {panel, clamp01(Map.get(factors, panel, 0.0))}
    end
  end

  defp render_canvas(%{display_info: display_info}, levels) do
    num_panels = max(div(display_info.width, @panel_width), 1)
    height = display_info.height

    # Gravity (0..1) maps directly to intensity (0..255) — no floor, no contrast.
    Enum.reduce(
      1..num_panels,
      Canvas.new(display_info.width, display_info.height, :grayscale),
      fn panel, canvas ->
        level = Map.get(levels, panel, 0.0)
        intensity = trunc(level * 255) |> max(0) |> min(255)

        x0 = (panel - 1) * @panel_width
        x1 = x0 + @panel_width - 1

        Canvas.fill_rect(canvas, {x0, 0}, {x1, height - 1}, intensity)
      end
    )
  end

  defp apply_gravity_config(config) when is_map(config) do
    case Map.get(config, :easing_tau) do
      nil -> :ok
      tau -> Radar.set_panel_gravity_config(easing_tau: tau)
    end
  end

  defp debug_due?(_now, nil), do: true

  defp debug_due?(now, last_debug_ms) when is_integer(last_debug_ms) do
    last_debug_ms == 0 or now - last_debug_ms >= @debug_log_interval_ms
  end

  defp log_display_debug(state, factors, levels) do
    factor_values = Map.values(factors)
    fac_max = Enum.max(factor_values, fn -> 0.0 end)

    top =
      levels
      |> Enum.sort_by(fn {_panel, level} -> -level end)
      |> Enum.take(5)
      |> Enum.map(fn {panel, level} ->
        intensity = trunc(level * 255) |> max(0) |> min(255)
        "p#{panel} lvl=#{Float.round(level, 3)} px=#{intensity}"
      end)
      |> Enum.join(" | ")

    Logger.debug(
      "[GravityMask] easing=#{state.easing_tau}s " <>
        "factors_max=#{Float.round(fac_max, 4)} | top: #{top}"
    )
  end

  defp clamp01(v), do: v |> max(0.0) |> min(1.0)
end
