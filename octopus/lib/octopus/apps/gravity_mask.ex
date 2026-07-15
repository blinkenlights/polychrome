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
  # Floor brightness as percent 0..100 in config / UI; stored as 0..1 unit internally.
  @default_floor_pct 25
  @default_contrast 3.0
  @default_reach 50
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
    %{
      floor_brightness: @default_floor_pct,
      contrast: @default_contrast,
      reach: @default_reach
    }
  end

  def mode_tweakables(mode_id) do
    mode_tweakables_for(apply(@mode_presets, :mode_slug, [mode_id]))
  end

  def mode_tweakables_for(slug) when slug in ["mask", "default"] do
    [
      %{
        key: :floor_brightness,
        label: "Floor brightness",
        type: :slider,
        min: 0,
        max: 100,
        step: 5,
        unit: "%",
        default: @default_floor_pct
      },
      %{
        key: :contrast,
        label: "Contrast",
        type: :slider,
        min: 1.0,
        max: 6.0,
        step: 0.5,
        default: @default_contrast
      },
      %{
        key: :reach,
        label: "Reach",
        type: :slider,
        min: 1,
        max: 100,
        step: 1,
        default: @default_reach
      }
    ]
  end

  def mode_tweakables_for(_), do: []

  def now_playing_meta(config) do
    floor_pct = floor_config_to_pct(Map.get(config, :floor_brightness, @default_floor_pct))
    reach = Map.get(config, :reach, @default_reach)

    [
      "floor #{trunc(floor_pct)}%",
      "reach #{trunc(reach)}"
    ]
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
      floor_brightness: floor_config_to_unit(Map.get(config, :floor_brightness, @default_floor_pct)),
      contrast: Map.get(config, :contrast, @default_contrast),
      reach: Map.get(config, :reach, @default_reach),
      last_debug_ms: nil
    }

    # One-shot initial paint from current snapshot (no polling loop).
    send(self(), :paint_now)

    Logger.debug(
      "[GravityMask] started floor=#{floor_config_to_pct(Map.get(config, :floor_brightness, @default_floor_pct))}% " <>
        "contrast=#{Map.get(config, :contrast, @default_contrast)} " <>
        "reach=#{Map.get(config, :reach, @default_reach)} " <>
        "panel_gravity=#{inspect(Process.whereis(Octopus.Radar.PanelGravity) != nil)}"
    )

    {:ok, state}
  end

  def handle_info(:paint_now, state) do
    factors =
      if Process.whereis(Octopus.Radar.PanelGravity) do
        Radar.panel_factors_gravity()
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
      floor_brightness:
        {"Floor brightness", :float, %{min: 0, max: 100, step: 5, default: @default_floor_pct}},
      contrast: {"Contrast", :float, %{min: 1.0, max: 6.0, step: 0.5, default: @default_contrast}},
      reach: {"Reach", :float, %{min: 1, max: 100, step: 1, default: @default_reach}}
    }
  end

  def get_config(state) do
    %{
      floor_brightness: floor_unit_to_pct(state.floor_brightness),
      contrast: state.contrast,
      reach: state.reach
    }
  end

  def handle_config(config, state) do
    apply_gravity_config(config)

    state = %{
      state
      | floor_brightness:
          floor_config_to_unit(
            Map.get(config, :floor_brightness, floor_unit_to_pct(state.floor_brightness))
          ),
        contrast: Map.get(config, :contrast, state.contrast),
        reach: Map.get(config, :reach, state.reach)
    }

    # Floor is display-local; reach/contrast notify PanelGravity via settings —
    # force a redraw now, and the next PubSub snapshot will refine if needed.
    {:noreply, maybe_render(state, force: true)}
  end

  defp factors_from_snapshot(snapshot, fallback) do
    case snapshot do
      %{target: target} when map_size(target) > 0 -> target
      %{gravity: gravity} when map_size(gravity) > 0 -> gravity
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

  defp render_canvas(
         %{display_info: display_info, floor_brightness: floor},
         levels
       ) do
    num_panels = max(div(display_info.width, @panel_width), 1)
    height = display_info.height

    # Install panel N → canvas column N-1 (Presence / firmware slot order).
    Enum.reduce(
      1..num_panels,
      Canvas.new(display_info.width, display_info.height, :grayscale),
      fn panel, canvas ->
        level = Map.get(levels, panel, 0.0)
        brightness = floor + (1.0 - floor) * level
        intensity = trunc(brightness * 255) |> max(0) |> min(255)

        x0 = (panel - 1) * @panel_width
        x1 = x0 + @panel_width - 1

        Canvas.fill_rect(canvas, {x0, 0}, {x1, height - 1}, intensity)
      end
    )
  end

  defp apply_gravity_config(config) when is_map(config) do
    opts =
      []
      |> maybe_put(:contrast, Map.get(config, :contrast))
      |> maybe_put(:reach, Map.get(config, :reach))

    if opts != [], do: Radar.set_panel_gravity_config(opts)

    :ok
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  # Monotonic ms can be negative (OTP/erts); never seed last_debug_ms with 0.
  defp debug_due?(_now, nil), do: true

  defp debug_due?(now, last_debug_ms) when is_integer(last_debug_ms) do
    last_debug_ms == 0 or now - last_debug_ms >= @debug_log_interval_ms
  end

  defp log_display_debug(state, factors, levels) do
    floor = state.floor_brightness
    factor_values = Map.values(factors)
    fac_min = Enum.min(factor_values, fn -> 0.0 end)
    fac_max = Enum.max(factor_values, fn -> 0.0 end)
    fac_span = fac_max - fac_min

    entries =
      levels
      |> Enum.map(fn {panel, level} ->
        factor = Map.get(factors, panel, 0.0)
        brightness = floor + (1.0 - floor) * level
        intensity = trunc(brightness * 255) |> max(0) |> min(255)
        {panel, factor, level, brightness, intensity}
      end)
      |> Enum.sort_by(fn {_panel, _factor, level, _brightness, _intensity} -> -level end)

    top =
      entries
      |> Enum.take(5)
      |> Enum.map(fn {panel, factor, level, brightness, intensity} ->
        "p#{panel} fac=#{Float.round(factor, 4)} lvl=#{Float.round(level, 3)} " <>
          "bri=#{trunc(brightness * 100)}% px=#{intensity}"
      end)
      |> Enum.join(" | ")

    Logger.debug(
      "[GravityMask] floor=#{trunc(floor * 100)}% factors_min=#{Float.round(fac_min, 4)} " <>
        "factors_max=#{Float.round(fac_max, 4)} span=#{Float.round(fac_span, 4)} | top: #{top}"
    )
  end

  # Config/UI use 0..100 percent. Accept legacy 0..1 fractions from older presets.
  defp floor_config_to_unit(v) when is_number(v) and v > 1.0, do: clamp01(v / 100.0)
  defp floor_config_to_unit(v) when is_number(v), do: clamp01(v)

  defp floor_config_to_pct(v) when is_number(v) and v > 1.0, do: v |> max(0.0) |> min(100.0)
  defp floor_config_to_pct(v) when is_number(v), do: clamp01(v) * 100.0

  defp floor_unit_to_pct(v), do: clamp01(v) * 100.0

  defp clamp01(v), do: v |> max(0.0) |> min(1.0)
end
