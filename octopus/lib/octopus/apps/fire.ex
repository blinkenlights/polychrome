defmodule Octopus.Apps.Fire do
  @moduledoc """
  Realistic fire animation based on FastLED Fire2012-style heat diffusion.

  Optimized for tall, narrow matrices (e.g. Woodstock 1×32 / 2×32): each column
  runs an independent 1D heat simulation with flame licks, lateral bleed when
  wider, and rising ember particles.
  """

  use Octopus.App, category: :animation

  @mode_presets Module.concat(["Octopus", "AppModePresets"])

  alias Octopus.Canvas
  alias Octopus.Installation

  @fps 45
  @frame_time_ms trunc(1000 / @fps)
  @max_embers 16
  @flicker_amp 0.08
  @min_flame_height 8

  defmodule State do
    @moduledoc false
    defstruct [
      :width,
      :height,
      :columns,
      :embers,
      :cooling,
      :sparking,
      :intensity,
      :ember_rate,
      :speed,
      :floor,
      :global_speed,
      :flicker
    ]
  end

  def name, do: "Fire"

  def compatible? do
    info = Octopus.App.get_installation_info()
    info.panel_count >= 1 and info.panel_height >= 8
  end

  def list_modes do
    apply(@mode_presets, :list_modes, [__MODULE__])
  end

  def mode_config(mode_id) do
    slug = apply(@mode_presets, :mode_slug, [mode_id])
    defaults = legacy_mode_config(slug)
    stored = apply(@mode_presets, :config_for, [__MODULE__, mode_id]) || %{}

    defaults
    |> Map.merge(stored)
    |> normalize_mode_config()
  end

  def normalize_mode_config(config) do
    %{
      cooling: Map.get(config, :cooling, 55) |> clamp_int(20, 120),
      sparking: Map.get(config, :sparking, 120) |> clamp_int(40, 255),
      intensity: Map.get(config, :intensity, 1.0) |> clamp_float(0.3, 1.5),
      ember_rate: Map.get(config, :ember_rate, 0.08) |> clamp_float(0.0, 1.0),
      speed: Map.get(config, :speed, 1.0) |> clamp_float(0.25, 2.5),
      floor: Map.get(config, :floor, 0) |> clamp_int(0, max_floor())
    }
  end

  def builtin_presets do
    [
      %{
        slug: "campfire",
        name: "Campfire",
        accent_color: "#E67E22",
        config: legacy_mode_config("campfire")
      },
      %{
        slug: "inferno",
        name: "Inferno",
        accent_color: "#E74C3C",
        config: legacy_mode_config("inferno")
      },
      %{
        slug: "embers",
        name: "Embers",
        accent_color: "#C0392B",
        config: legacy_mode_config("embers")
      }
    ]
  end

  def legacy_mode_config("campfire") do
    %{
      cooling: 55,
      sparking: 120,
      intensity: 1.0,
      ember_rate: 0.08,
      speed: 1.0,
      floor: 0
    }
  end

  def legacy_mode_config("inferno") do
    %{
      cooling: 35,
      sparking: 190,
      intensity: 1.25,
      ember_rate: 0.12,
      speed: 1.2,
      floor: 0
    }
  end

  def legacy_mode_config("embers") do
    %{
      cooling: 80,
      sparking: 70,
      intensity: 0.7,
      ember_rate: 0.35,
      speed: 0.85,
      floor: 0
    }
  end

  def legacy_mode_config(_), do: legacy_mode_config("campfire")

  def mode_tweakables(mode_id) do
    mode_tweakables_for(apply(@mode_presets, :mode_slug, [mode_id]))
  end

  def mode_tweakables_for(_slug) do
    [
      %{
        key: :floor,
        label: "Floor",
        type: :slider,
        min: 0,
        max: max_floor(),
        step: 1,
        default: 0
      },
      %{
        key: :cooling,
        label: "Cooling",
        type: :slider,
        min: 20,
        max: 120,
        step: 1,
        default: 55
      },
      %{
        key: :sparking,
        label: "Sparking",
        type: :slider,
        min: 40,
        max: 255,
        step: 1,
        default: 120
      },
      %{
        key: :intensity,
        label: "Intensity",
        type: :slider,
        min: 0.3,
        max: 1.5,
        step: 0.05,
        default: 1.0
      },
      %{
        key: :ember_rate,
        label: "Embers",
        type: :slider,
        min: 0.0,
        max: 1.0,
        step: 0.05,
        default: 0.08
      },
      %{
        key: :speed,
        label: "Speed",
        type: :slider,
        min: 0.25,
        max: 2.5,
        step: 0.05,
        default: 1.0
      }
    ]
  end

  def now_playing_meta(config) do
    cooling = Map.get(config, :cooling, 55)
    sparking = Map.get(config, :sparking, 120)
    intensity = Map.get(config, :intensity, 1.0)
    floor = Map.get(config, :floor, 0)

    [
      "floor #{floor}",
      "cool #{cooling}",
      "spark #{sparking}",
      "int #{format_num(intensity)}"
    ]
  end

  def config_schema do
    %{
      floor: {"Floor", :int, %{min: 0, max: max_floor(), default: 0}},
      cooling: {"Cooling", :int, %{min: 20, max: 120, default: 55}},
      sparking: {"Sparking", :int, %{min: 40, max: 255, default: 120}},
      intensity: {"Intensity", :float, %{min: 0.3, max: 1.5, default: 1.0}},
      ember_rate: {"Embers", :float, %{min: 0.0, max: 1.0, default: 0.08}},
      speed: {"Speed", :float, %{min: 0.25, max: 2.5, default: 1.0}}
    }
  end

  def get_config(%State{} = state) do
    %{
      floor: state.floor,
      cooling: state.cooling,
      sparking: state.sparking,
      intensity: state.intensity,
      ember_rate: state.ember_rate,
      speed: state.speed
    }
  end

  def handle_config(config, %State{} = state) do
    cfg = normalize_mode_config(config)
    floor = min(cfg.floor, max_floor(state.height))

    {:noreply,
     %{
       state
       | floor: floor,
         cooling: cfg.cooling,
         sparking: cfg.sparking,
         intensity: cfg.intensity,
         ember_rate: cfg.ember_rate,
         speed: cfg.speed
     }}
  end

  def app_init(config) do
    Octopus.App.configure_display(layout: :adjacent_panels, easing_interval: 0)
    Octopus.Params.Global.subscribe()

    display_info = Octopus.App.get_display_info()
    width = display_info.width
    height = display_info.height
    cfg = normalize_mode_config(config || %{})
    floor = min(cfg.floor, max_floor(height))

    Process.send_after(self(), :tick, @frame_time_ms)

    {:ok,
     %State{
       width: width,
       height: height,
       columns: new_columns(width, height),
       embers: [],
       cooling: cfg.cooling,
       sparking: cfg.sparking,
       intensity: cfg.intensity,
       ember_rate: cfg.ember_rate,
       speed: cfg.speed,
       floor: floor,
       global_speed: Octopus.Params.Global.speed(),
       flicker: List.duplicate(1.0, width)
     }}
  end

  def handle_info({:param_updated, :speed, value}, %State{} = state) do
    {:noreply, %{state | global_speed: value}}
  end

  def handle_info({:param_updated, _key, _value}, state), do: {:noreply, state}

  def handle_info(:tick, %State{} = state) do
    tick_start = System.monotonic_time(:millisecond)

    speed_factor = state.speed * (0.85 + 0.15 * state.global_speed)
    steps = max(1, round(speed_factor))

    state =
      Enum.reduce(1..steps, state, fn _, s ->
        s
        |> step_heat()
        |> update_flicker()
        |> maybe_spawn_embers()
        |> update_embers(1.0 / @fps)
      end)

    canvas = render(state)
    Octopus.App.update_display(canvas)

    elapsed = System.monotonic_time(:millisecond) - tick_start
    # Faster speed shortens the wait between ticks slightly.
    interval = trunc(@frame_time_ms / max(speed_factor, 0.5))
    Process.send_after(self(), :tick, max(interval - elapsed, 1))

    {:noreply, state}
  end

  # ---------------------------------------------------------------------------
  # Heat simulation (Fire2012 per column, y=0 at base)
  # ---------------------------------------------------------------------------

  defp new_columns(width, height) do
    zero_col = List.duplicate(0, height) |> List.to_tuple()
    List.duplicate(zero_col, width)
  end

  defp step_heat(%State{} = state) do
    floor = state.floor
    flame_h = max(state.height - floor, @min_flame_height)

    columns =
      state.columns
      |> Enum.with_index()
      |> Enum.map(fn {col, x} ->
        col
        |> cool_column(state.height, floor, state.cooling, flame_h)
        |> rise_column(state.height, floor)
        |> spark_column(state.height, floor, flame_h, state.sparking, x)
        |> maybe_flame_lick(state.height, floor, flame_h)
        |> clear_below_floor(floor)
      end)

    columns =
      if state.width > 1 do
        lateral_bleed(columns, state.height, floor)
      else
        columns
      end

    %{state | columns: columns}
  end

  defp cool_column(col, height, floor, cooling, flame_h) do
    # FastLED: random8(0, ((COOLING * 10) / NUM_LEDS) + 2) — scale by flame height
    cool_range = max(trunc(cooling * 10 / flame_h) + 2, 2)

    for y <- 0..(height - 1) do
      cond do
        y < floor ->
          0

        true ->
          heat = elem(col, y)
          loss = :rand.uniform(cool_range) - 1
          max(heat - loss, 0)
      end
    end
    |> List.to_tuple()
  end

  defp rise_column(col, _height, floor) when floor >= tuple_size(col) - 2, do: col

  defp rise_column(col, height, floor) do
    # Work top-down so we sample pre-rise neighbors (Fire2012).
    # Only rise within the flame band above the floor.
    start_y = floor + 2

    if start_y >= height do
      col
    else
      Enum.reduce((height - 1)..start_y//-1, col, fn y, acc ->
        a = elem(acc, y - 1)
        b = elem(acc, max(y - 2, floor))
        put_elem(acc, y, div(a + b + b, 3))
      end)
    end
  end

  defp spark_column(col, height, floor, flame_h, sparking, x) do
    # Stagger spark chance slightly by column so adjacent columns desync.
    phase = rem(x * 37, 40)
    chance = min(sparking + phase - 20, 255)

    if :rand.uniform(255) - 1 < chance do
      band = max(trunc(flame_h * 0.15), 2)
      y = floor + :rand.uniform(band) - 1
      y = min(y, height - 1)
      boost = 160 + :rand.uniform(96) - 1
      put_elem(col, y, min(elem(col, y) + boost, 255))
    else
      col
    end
  end

  defp maybe_flame_lick(col, height, floor, flame_h) do
    # ~2% chance: inject a tall lick near the floor.
    if :rand.uniform(100) <= 2 do
      base = floor + :rand.uniform(max(div(flame_h, 8), 1)) - 1
      base = min(base, height - 1)
      heat = 220 + :rand.uniform(36) - 1

      Enum.reduce(0..min(3, height - 1 - base), col, fn dy, acc ->
        y = base + dy
        fade = trunc(heat * (1.0 - dy * 0.2))
        put_elem(acc, y, min(max(elem(acc, y), fade), 255))
      end)
    else
      col
    end
  end

  defp clear_below_floor(col, 0), do: col

  defp clear_below_floor(col, floor) do
    Enum.reduce(0..(floor - 1), col, fn y, acc -> put_elem(acc, y, 0) end)
  end

  defp lateral_bleed(columns, height, floor) do
    width = length(columns)

    for x <- 0..(width - 1) do
      self = Enum.at(columns, x)
      left = Enum.at(columns, max(x - 1, 0))
      right = Enum.at(columns, min(x + 1, width - 1))

      for y <- 0..(height - 1) do
        if y < floor do
          0
        else
          s = elem(self, y)
          l = elem(left, y)
          r = elem(right, y)
          # ~16% neighbor influence keeps columns coupled but not identical.
          trunc(s * 0.84 + l * 0.08 + r * 0.08)
        end
      end
      |> List.to_tuple()
    end
  end

  defp update_flicker(%State{width: width, flicker: flicker} = state) do
    flicker =
      Enum.map(flicker, fn f ->
        target = 1.0 + (:rand.uniform() - 0.5) * 2 * @flicker_amp
        f + (target - f) * 0.35
      end)

    # Pad/truncate if width somehow changed (shouldn't during runtime).
    flicker =
      cond do
        length(flicker) < width ->
          flicker ++ List.duplicate(1.0, width - length(flicker))

        length(flicker) > width ->
          Enum.take(flicker, width)

        true ->
          flicker
      end

    %{state | flicker: flicker}
  end

  # ---------------------------------------------------------------------------
  # Embers (rising sparks; custom — Particles gravity pulls downward)
  # ---------------------------------------------------------------------------

  defp maybe_spawn_embers(%State{} = state) do
    if length(state.embers) >= @max_embers or state.ember_rate <= 0 do
      state
    else
      # Chance scaled by ember_rate; prefer hot cells near the floor.
      if :rand.uniform() < state.ember_rate * 0.4 do
        x = :rand.uniform(state.width) - 1
        col = Enum.at(state.columns, x)
        flame_h = max(state.height - state.floor, @min_flame_height)
        band = max(div(flame_h, 5), 1)
        base_y = state.floor + :rand.uniform(band) - 1
        base_y = min(base_y, state.height - 1)
        heat = elem(col, base_y)

        if heat > 140 do
          ember = %{
            x: x + (:rand.uniform() - 0.5) * 0.4,
            # sim y=0 base → canvas y = height - 1 - y; spawn slightly above floor
            y: state.height - 1 - base_y - :rand.uniform() * 0.5,
            vy: -(4.0 + :rand.uniform() * 10.0) * state.speed,
            vx: (:rand.uniform() - 0.5) * 1.5,
            ttl: 0.35 + :rand.uniform() * 0.9,
            color: ember_color(heat)
          }

          %{state | embers: [ember | state.embers]}
        else
          state
        end
      else
        state
      end
    end
  end

  defp update_embers(%State{embers: embers, width: width, height: height} = state, dt) do
    embers =
      embers
      |> Enum.map(fn e ->
        %{
          e
          | x: e.x + e.vx * dt,
            y: e.y + e.vy * dt,
            # slow as they rise / cool
            vy: e.vy * (1.0 - 0.4 * dt),
            ttl: e.ttl - dt
        }
      end)
      |> Enum.filter(fn e ->
        e.ttl > 0 and e.x >= -0.5 and e.x < width + 0.5 and e.y >= -0.5 and e.y < height + 0.5
      end)
      |> Enum.take(@max_embers)

    %{state | embers: embers}
  end

  defp ember_color(heat) do
    cond do
      heat > 220 -> {255, 240, 180}
      heat > 180 -> {255, 200, 80}
      true -> {255, 140, 40}
    end
  end

  # ---------------------------------------------------------------------------
  # Render
  # ---------------------------------------------------------------------------

  defp render(%State{} = state) do
    canvas = Canvas.new(state.width, state.height)

    canvas =
      for x <- 0..(state.width - 1),
          y_sim <- 0..(state.height - 1),
          into: canvas do
        heat = elem(Enum.at(state.columns, x), y_sim)
        heat = trunc(min(heat * state.intensity, 255))
        flicker = Enum.at(state.flicker, x) || 1.0
        {r, g, b} = heat_color(heat)
        color = scale_rgb({r, g, b}, flicker)
        canvas_y = state.height - 1 - y_sim
        {{x, canvas_y}, color}
      end

    Enum.reduce(state.embers, canvas, fn ember, canvas ->
      px = round(ember.x)
      py = round(ember.y)

      if px >= 0 and px < state.width and py >= 0 and py < state.height do
        fade = min(ember.ttl / 0.5, 1.0)
        color = scale_rgb(ember.color, fade)
        Canvas.put_pixel(canvas, {px, py}, color)
      else
        canvas
      end
    end)
  end

  # FastLED HeatColor: black → red → yellow → white
  defp heat_color(0), do: {0, 0, 0}

  defp heat_color(temperature) when temperature > 0 do
    t192 = trunc(temperature * 191 / 255)
    heatramp = Bitwise.band(t192, 0x3F) * 4

    cond do
      Bitwise.band(t192, 0x80) != 0 ->
        {255, 255, heatramp}

      Bitwise.band(t192, 0x40) != 0 ->
        {255, heatramp, 0}

      true ->
        {heatramp, 0, 0}
    end
  end

  defp scale_rgb({r, g, b}, factor) do
    f = max(factor, 0.0)

    {
      min(trunc(r * f), 255),
      min(trunc(g * f), 255),
      min(trunc(b * f), 255)
    }
  end

  defp max_floor do
    max_floor(Installation.panel_height())
  end

  defp max_floor(height) when is_integer(height) and height > @min_flame_height do
    height - @min_flame_height
  end

  defp max_floor(_), do: 0

  defp clamp_int(v, min_v, max_v) when is_number(v) do
    v |> trunc() |> max(min_v) |> min(max_v)
  end

  defp clamp_int(_, min_v, _), do: min_v

  defp clamp_float(v, min_v, max_v) when is_number(v) do
    v / 1 |> max(min_v) |> min(max_v)
  end

  defp clamp_float(_, min_v, _), do: min_v

  defp format_num(n) when is_float(n), do: :erlang.float_to_binary(n, decimals: 2)
  defp format_num(n), do: to_string(n)
end
