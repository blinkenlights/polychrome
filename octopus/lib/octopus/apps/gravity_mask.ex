defmodule Octopus.Apps.GravityMask do
  @moduledoc """
  Greyscale proximity mask driven by per-panel gravity from radar tracks.

  Subscribes to `Octopus.Radar.PanelGravity` and maps normalised gravity
  factors to panel brightness (configurable floor, default 25%–100%).
  """

  use Octopus.App, category: :animation, output_type: :grayscale

  require Logger

  alias Octopus.Canvas
  alias Octopus.Installation
  alias Octopus.Radar
  alias Octopus.Radar.PanelMapping

  @panel_width 8
  @default_tick_hz 25
  @debug_log_interval_ms 1_000

  def name, do: "Gravity Mask"

  def compatible? do
    Installation.arrangement() == :circular and Radar.configured?()
  end

  def app_init(config) do
    Octopus.App.configure_display(
      layout: :adjacent_panels,
      supports_rgb: false,
      supports_grayscale: true,
      easing_interval: 50
    )

    display_info = Octopus.App.get_display_info()
    tick_hz = Map.get(config, :tick_hz, @default_tick_hz)

    if Process.whereis(Octopus.Radar.PanelGravity) do
      :ok = Radar.subscribe_panel_gravity()
    end

    schedule_tick(tick_hz)

    {:ok,
     %{
       display_info: display_info,
       factors: Radar.panel_factors_gravity(),
       floor_brightness: Map.get(config, :floor_brightness, 0.25) |> clamp_floor(),
       tick_hz: tick_hz,
       last_debug_ms: 0
     }}
  end

  def handle_info({:panel_gravity, %{gravity: gravity}}, state) do
    {:noreply, %{state | factors: gravity}}
  end

  def handle_info(:tick, state) do
    schedule_tick(state.tick_hz)

    canvas = render_canvas(state)
    Octopus.App.update_display(canvas, :grayscale)

    factors = Radar.panel_factors_gravity()
    now = :erlang.monotonic_time(:millisecond)

    state =
      if debug_due?(now, state.last_debug_ms, factors) do
        log_display_debug(state, factors)
        %{state | last_debug_ms: now}
      else
        state
      end

    {:noreply, %{state | factors: factors}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  def config_schema do
    %{
      floor_brightness:
        {"Floor brightness", :float, %{min: 0.25, max: 0.75, step: 0.05, default: 0.25}},
      tick_hz: {"Refresh rate (Hz)", :int, %{min: 10, max: 60, default: @default_tick_hz}}
    }
  end

  def get_config(%{floor_brightness: floor_brightness, tick_hz: tick_hz}) do
    %{floor_brightness: floor_brightness, tick_hz: tick_hz}
  end

  def handle_config(config, state) do
    {:noreply,
     %{
       state
       | floor_brightness:
           Map.get(config, :floor_brightness, state.floor_brightness) |> clamp_floor(),
         tick_hz: Map.get(config, :tick_hz, state.tick_hz)
     }}
  end

  defp render_canvas(%{display_info: display_info, factors: factors, floor_brightness: floor}) do
    num_panels = max(div(display_info.width, @panel_width), 1)
    height = display_info.height
    north_panel = Radar.north_panel()

    Enum.reduce(
      1..num_panels,
      Canvas.new(display_info.width, display_info.height, :grayscale),
      fn panel, canvas ->
        level = Map.get(factors, panel, 0.0) |> clamp01()
        brightness = floor + (1.0 - floor) * level
        intensity = trunc(brightness * 255) |> max(0) |> min(255)

        frame_panel =
          PanelMapping.frame_panel_for_installation(panel, num_panels, north_panel)

        x0 = frame_panel * @panel_width
        x1 = x0 + @panel_width - 1

        Canvas.fill_rect(canvas, {x0, 0}, {x1, height - 1}, intensity)
      end
    )
  end

  defp schedule_tick(hz) when is_integer(hz) and hz > 0 do
    interval = max(trunc(1000 / hz), 1)
    Process.send_after(self(), :tick, interval)
  end

  defp debug_due?(now, last_debug_ms, factors) do
    Enum.any?(factors, fn {_panel, value} -> value > 0.01 end) and
      now - last_debug_ms >= @debug_log_interval_ms
  end

  defp log_display_debug(state, factors) do
    floor = state.floor_brightness

    entries =
      factors
      |> Enum.map(fn {panel, level} ->
        level = clamp01(level)
        brightness = floor + (1.0 - floor) * level
        intensity = trunc(brightness * 255) |> max(0) |> min(255)
        {panel, level, brightness, intensity}
      end)
      |> Enum.sort_by(fn {_panel, level, _brightness, _intensity} -> -level end)
      |> Enum.take(3)

    top =
      entries
      |> Enum.map(fn {panel, level, brightness, intensity} ->
        "p#{panel} lvl=#{Float.round(level, 3)} bri=#{trunc(brightness * 100)}% px=#{intensity}"
      end)
      |> Enum.join(" ")

    Logger.debug("[GravityMask] floor=#{trunc(floor * 100)}% display=[#{top}]")
  end

  defp clamp_floor(v), do: v |> max(0.25) |> min(0.75) |> clamp01()
  defp clamp01(v), do: v |> max(0.0) |> min(1.0)
end
