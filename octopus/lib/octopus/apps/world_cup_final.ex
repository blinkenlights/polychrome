defmodule Octopus.Apps.WorldCupFinal do
  @moduledoc """
  Alternating fluttering flags for tall strips and larger matrices.

  With **dual-sided** enabled, the canvas is split vertically in the middle and each
  half shows the same single-column flag (Woodstock front/back). Otherwise the flag
  fills the full matrix width.

  On narrow strips, flags gently sway left and right around their horizontal center so
  crosses, suns, and other centered details can pass through the viewport.

  **Floor** leaves the bottom N rows dark; presets use floor 8 on Woodstock (top 24
  of 32). Default floor is 0 so other installations use the full height.
  """

  use Octopus.App, category: :animation

  @mode_presets Module.concat(["Octopus", "AppModePresets"])

  alias Octopus.Canvas
  alias Octopus.Events.Event.Lifecycle, as: LifecycleEvent

  @fps 30
  @frame_time_ms trunc(1000 / @fps)
  @min_panel_height 8
  @min_visible_rows 1

  @flag_options [
    {:argentina, "Argentina"},
    {:spain, "Spain"},
    {:france, "France"},
    {:england, "England"},
    {:italy, "Italy"},
    {:germany, "Germany"},
    {:netherlands, "Netherlands"},
    {:belgium, "Belgium"},
    {:brazil, "Brazil"}
  ]

  @known_flags Enum.map(@flag_options, fn {flag, _} -> flag end)

  @argentina_blue {117, 170, 219}
  @argentina_white {255, 255, 255}
  @argentina_sun {246, 180, 14}
  @spain_red {170, 21, 27}
  @spain_yellow {241, 191, 0}
  @england_white {255, 255, 255}
  @england_red {207, 19, 43}

  defmodule State do
    @moduledoc false
    defstruct [
      :anim_time,
      :started_at_ms,
      :global_speed,
      :next_tick_at,
      :flag_a,
      :flag_b,
      :hold_s,
      :crossfade_s,
      :dual_sided,
      :floor
    ]
  end

  def name, do: "World Cup Final"

  def compatible? do
    info = Octopus.App.get_installation_info()

    info.panel_count >= 1 and info.panel_height >= @min_panel_height
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
      flag_a: Map.get(config, :flag_a, :argentina) |> coerce_flag(),
      flag_b: Map.get(config, :flag_b, :spain) |> coerce_flag(),
      hold_s: Map.get(config, :hold_s, 12.0) |> clamp_float(2.0, 30.0),
      crossfade_s: Map.get(config, :crossfade_s, 0.6) |> clamp_float(0.1, 3.0),
      dual_sided: Map.get(config, :dual_sided, false) |> coerce_bool(),
      floor: Map.get(config, :floor, 0) |> clamp_int(0, 512)
    }
  end

  def legacy_mode_config("world_cup_half_final") do
    %{
      flag_a: :england,
      flag_b: :france,
      hold_s: 12.0,
      crossfade_s: 0.6,
      dual_sided: true,
      floor: 8
    }
  end

  def legacy_mode_config("world_cup_final") do
    %{
      flag_a: :argentina,
      flag_b: :spain,
      hold_s: 12.0,
      crossfade_s: 0.6,
      dual_sided: true,
      floor: 8
    }
  end

  def legacy_mode_config(_), do: legacy_mode_config("world_cup_final")

  def mode_tweakables(mode_id) do
    mode_tweakables_for(apply(@mode_presets, :mode_slug, [mode_id]))
  end

  def mode_tweakables_for(_slug) do
    [
      %{
        key: :flag_a,
        label: "First flag",
        type: :choice,
        default: :argentina,
        options: @flag_options
      },
      %{
        key: :flag_b,
        label: "Second flag",
        type: :choice,
        default: :spain,
        options: @flag_options
      },
      %{
        key: :hold_s,
        label: "Hold (s)",
        type: :slider,
        min: 2.0,
        max: 30.0,
        step: 0.5,
        default: 12.0
      },
      %{
        key: :crossfade_s,
        label: "Crossfade (s)",
        type: :slider,
        min: 0.1,
        max: 3.0,
        step: 0.1,
        default: 0.6
      },
      %{
        key: :dual_sided,
        label: "Dual-sided mirror",
        type: :toggle,
        default: false
      },
      %{
        key: :floor,
        label: "Floor",
        type: :slider,
        min: 0,
        max: max_floor(),
        step: 1,
        default: 0
      }
    ]
  end

  def now_playing_meta(config) do
    cfg = normalize_mode_config(config)

    meta =
      [
        flag_label(cfg.flag_a),
        flag_label(cfg.flag_b),
        "hold #{format_num(cfg.hold_s)}s"
      ] ++
        if(cfg.dual_sided, do: ["dual-sided"], else: []) ++
        if(cfg.floor > 0, do: ["floor #{cfg.floor}"], else: [])

    meta
  end

  def config_schema do
    flag_options = Enum.map(@flag_options, fn {flag, label} -> {label, flag} end)

    [
      flag_a:
        {"First flag", :select,
         %{
           default: 0,
           options: flag_options
         }},
      flag_b:
        {"Second flag", :select,
         %{
           default: 1,
           options: flag_options
         }},
      hold_s: {"Hold (s)", :float, %{default: 12.0, min: 2.0, max: 30.0, step: 0.5}},
      crossfade_s: {"Crossfade (s)", :float, %{default: 0.6, min: 0.1, max: 3.0, step: 0.1}},
      dual_sided: {"Dual-sided mirror", :boolean, %{default: false}},
      floor: {"Floor", :int, %{default: 0, min: 0, max: max_floor()}}
    ]
  end

  def get_config(%State{} = state) do
    %{
      flag_a: state.flag_a,
      flag_b: state.flag_b,
      hold_s: state.hold_s,
      crossfade_s: state.crossfade_s,
      dual_sided: state.dual_sided,
      floor: state.floor
    }
  end

  def handle_config(config, %State{} = state) do
    cfg = normalize_mode_config(Map.merge(get_config(state), config))

    new_state = %{
      state
      | flag_a: cfg.flag_a,
        flag_b: cfg.flag_b,
        hold_s: cfg.hold_s,
        crossfade_s: cfg.crossfade_s,
        dual_sided: cfg.dual_sided,
        floor: cfg.floor
    }

    render(new_state)
    {:noreply, new_state}
  end

  def app_init(config) do
    Octopus.App.configure_display(layout: :adjacent_panels)
    Octopus.Params.Global.subscribe()

    cfg = normalize_mode_config(config || %{})
    now = System.monotonic_time(:millisecond)

    state = %State{
      anim_time: 0.0,
      started_at_ms: now,
      global_speed: Octopus.Params.Global.speed(),
      next_tick_at: now + @frame_time_ms,
      flag_a: cfg.flag_a,
      flag_b: cfg.flag_b,
      hold_s: cfg.hold_s,
      crossfade_s: cfg.crossfade_s,
      dual_sided: cfg.dual_sided,
      floor: cfg.floor
    }

    render(state)
    schedule_tick(now)

    {:ok, state}
  end

  def handle_event(%LifecycleEvent{type: :app_selected}, state) do
    render(state)
    {:noreply, state}
  end

  def handle_event(_, state), do: {:noreply, state}

  def handle_info({:param_updated, :speed, global_speed}, %State{} = state) do
    {:noreply, %{state | global_speed: global_speed}}
  end

  def handle_info({:param_updated, _, _}, %State{} = state), do: {:noreply, state}

  def handle_info(:tick, %State{} = state) do
    now = System.monotonic_time(:millisecond)
    anim_dt = @frame_time_ms / 1000 * state.global_speed
    state = %{state | anim_time: state.anim_time + anim_dt}
    render(state)
    schedule_tick(now)
    {:noreply, %{state | next_tick_at: now + @frame_time_ms}}
  end

  @doc false
  def render_canvas(width, height, anim_time, flag_time, config) do
    cfg = normalize_mode_config(config)
    canvas = Canvas.new(width, height)
    visible_rows = visible_rows(height, cfg.floor)
    last_row = visible_rows - 1
    strip_width = flag_strip_width(width, cfg.dual_sided)

    for y <- 0..last_row,
        x <- 0..(width - 1),
        reduce: canvas do
      canvas ->
        local_x = flag_local_x(x, width, cfg.dual_sided)

        color =
          fluttered_pixel_color(
            x,
            local_x,
            y,
            strip_width,
            visible_rows,
            anim_time,
            flag_time,
            cfg
          )

        Canvas.put_pixel(canvas, {x, y}, color)
    end
  end

  @doc false
  def visible_rows(height, floor) when is_integer(height) and height > 0 do
    floor = floor |> clamp_int(0, max_floor(height))
    max(height - floor, @min_visible_rows)
  end

  @doc false
  def max_floor(height \\ Octopus.Installation.panel_height())

  def max_floor(height) when is_integer(height) and height > @min_visible_rows do
    height - @min_visible_rows
  end

  def max_floor(_height), do: 0

  @doc false
  def flag_strip_width(width, true) do
    width |> div(2) |> max(1)
  end

  def flag_strip_width(width, false), do: max(width, 1)

  @doc false
  def flag_local_x(x, width, true) do
    half = div(width, 2) |> max(1)
    rem(x, half)
  end

  def flag_local_x(x, _width, false), do: x

  @doc false
  def flag_color(flag, t, local_x \\ 0, strip_width \\ 1, sample_u \\ nil) do
    t = clamp01(t)

    case coerce_flag(flag) do
      :argentina -> argentina_color(t, sample_u)
      :spain -> spain_color(t)
      :france -> tricolor_color(t, {0, 85, 164}, @argentina_white, {239, 65, 53})
      :england -> england_color(t, local_x, strip_width, sample_u)
      :italy -> tricolor_color(t, {0, 140, 69}, @argentina_white, {206, 43, 55})
      :germany -> tricolor_color(t, {0, 0, 0}, {221, 0, 0}, {255, 206, 0})
      :netherlands -> tricolor_color(t, {174, 28, 40}, @argentina_white, {33, 70, 139})
      :belgium -> tricolor_color(t, {0, 0, 0}, {255, 223, 0}, {237, 41, 57})
      :brazil -> brazil_color(t, sample_u)
      _ -> argentina_color(t, sample_u)
    end
  end

  @doc false
  def flag_sample_u(local_x, strip_width, anim_time) when is_number(anim_time) do
    virtual_width = virtual_flag_width(strip_width)
    sway = horizontal_sway(anim_time, strip_width)
    scroll = (virtual_width - strip_width) / 2 + sway
    sample_x = scroll + local_x

    sample_x
    |> Kernel./(max(virtual_width - 1, 1))
    |> clamp01()
  end

  @doc false
  def active_flag(time, config) when time >= 0 do
    %{flag_a: flag_a, flag_b: flag_b, hold_s: hold_s} = normalize_mode_config(config)

    if rem(trunc(time / hold_s), 2) == 0, do: flag_a, else: flag_b
  end

  @doc false
  def flag_blend(time, config) when time >= 0 do
    %{flag_a: flag_a, flag_b: flag_b, hold_s: hold_s, crossfade_s: fade} = normalize_mode_config(config)
    cycle_pos = :math.fmod(time, hold_s * 2)

    cond do
      cycle_pos < hold_s - fade ->
        {flag_a, 1.0}

      cycle_pos < hold_s ->
        t = (cycle_pos - (hold_s - fade)) / fade
        {:crossfade, flag_a, flag_b, t}

      cycle_pos < hold_s * 2 - fade ->
        {flag_b, 1.0}

      true ->
        t = (cycle_pos - (hold_s * 2 - fade)) / fade
        {:crossfade, flag_b, flag_a, t}
    end
  end

  defp render(%State{} = state) do
    display_info = Octopus.App.get_display_info()
    flag_time = flag_time_s(state)

    canvas =
      render_canvas(
        display_info.width,
        display_info.height,
        state.anim_time,
        flag_time,
        get_config(state)
      )

    Octopus.App.update_display(canvas)
  end

  defp flag_time_s(%State{started_at_ms: started_at_ms}) do
    (System.monotonic_time(:millisecond) - started_at_ms) / 1000
  end

  defp schedule_tick(now) do
    delay = max(trunc(@frame_time_ms - (System.monotonic_time(:millisecond) - now)), 1)
    Process.send_after(self(), :tick, delay)
  end

  defp fluttered_pixel_color(x, local_x, y, strip_width, visible_rows, anim_time, flag_time, config) do
    visible_last = max(visible_rows - 1, 0)
    phase = anim_time * 2.8
    flutter_x = if config.dual_sided, do: local_x, else: x

    wave =
      :math.sin(y * 0.52 + phase + flutter_x * 0.35) * 1.15 +
        :math.sin(y * 0.31 - phase * 0.85 + flutter_x * 0.18) * 0.62 +
        :math.sin(y * 0.78 + phase * 1.35 + strip_width * 0.05) * 0.34

    twist = :math.sin(y * 0.44 + phase * 1.1 + flutter_x * 0.5) * 0.38

    src_y =
      (y + wave + twist)
      |> max(0)
      |> min(visible_last)

    t = if visible_last == 0, do: 0.0, else: src_y / visible_last
    sample_u = flag_sample_u(local_x, strip_width, anim_time)

    base =
      case flag_blend(flag_time, config) do
        {flag, 1.0} ->
          flag_color(flag, t, local_x, strip_width, sample_u)

        {:crossfade, from, to, mix} ->
          {r1, g1, b1} = flag_color(from, t, local_x, strip_width, sample_u)
          {r2, g2, b2} = flag_color(to, t, local_x, strip_width, sample_u)
          mix_rgb({r1, g1, b1}, {r2, g2, b2}, mix)
      end

    fold =
      0.76 +
        0.24 *
          :math.sin(y * 0.41 + phase * 2.2 + flutter_x * 0.4) *
          :math.sin(y * 0.19 - phase * 0.6 + flutter_x * 0.25)

    scale_color(base, fold)
  end

  defp argentina_color(t, sample_u) do
    cond do
      t < 1 / 3 ->
        @argentina_blue

      t > 2 / 3 ->
        @argentina_blue

      sun_strength(t, sample_u) >= 0.05 ->
        mix_rgb(@argentina_white, @argentina_sun, sun_strength(t, sample_u))

      true ->
        @argentina_white
    end
  end

  defp spain_color(t) do
    cond do
      t < 0.25 -> @spain_red
      t > 0.75 -> @spain_red
      true -> @spain_yellow
    end
  end

  defp england_color(t, local_x, strip_width, sample_u) do
    cond do
      strip_width <= 1 and is_nil(sample_u) ->
        england_color_single_column_legacy(t)

      strip_width <= 1 ->
        england_color_single_column(t, sample_u)

      is_nil(sample_u) ->
        england_color_wide(t, local_x, strip_width)

      true ->
        england_color_wide_u(t, sample_u)
    end
  end

  defp england_color_single_column_legacy(t) do
    horizontal_bar = t >= 0.38 and t <= 0.62
    vertical_stroke = t >= 0.18 and t <= 0.82

    if horizontal_bar or vertical_stroke do
      @england_red
    else
      @england_white
    end
  end

  defp england_color_single_column(t, u) do
    horizontal_bar = t >= 0.38 and t <= 0.62
    vertical_bar = abs(u - 0.5) <= 0.14 and t >= 0.14 and t <= 0.86

    if horizontal_bar or vertical_bar do
      @england_red
    else
      @england_white
    end
  end

  defp england_color_wide(t, local_x, strip_width) do
    horizontal_bar = t >= 0.38 and t <= 0.62
    vertical_bar = local_x >= div(strip_width, 2)

    if horizontal_bar or vertical_bar do
      @england_red
    else
      @england_white
    end
  end

  defp england_color_wide_u(t, u) do
    horizontal_bar = t >= 0.38 and t <= 0.62
    vertical_bar = abs(u - 0.5) <= 0.08

    if horizontal_bar or vertical_bar do
      @england_red
    else
      @england_white
    end
  end

  defp tricolor_color(t, top, middle, bottom) do
    cond do
      t < 1 / 3 -> top
      t > 2 / 3 -> bottom
      true -> middle
    end
  end

  defp brazil_color(t, sample_u) do
    diamond =
      cond do
        is_nil(sample_u) ->
          t >= 0.35 and t <= 0.65

        true ->
          t >= 0.35 and t <= 0.65 and abs(sample_u - 0.5) <= 0.22
      end

    cond do
      t < 0.35 -> {0, 155, 58}
      t > 0.65 -> {0, 155, 58}
      diamond -> {255, 223, 0}
      true -> {0, 155, 58}
    end
  end

  defp sun_strength(t, sample_u) do
    center = 0.5
    radius = 0.11
    dist = abs(t - center) / radius

    vertical =
      if dist >= 1.0 do
        0.0
      else
        (1.0 - dist) * (1.0 - dist)
      end

    case sample_u do
      nil ->
        vertical

      u ->
        horizontal = center_focus(u, 0.16)
        vertical * horizontal
    end
  end

  defp center_focus(u, radius) do
    dist = abs(u - 0.5) / radius

    if dist >= 1.0 do
      0.0
    else
      (1.0 - dist) * (1.0 - dist)
    end
  end

  defp virtual_flag_width(1), do: 5.0
  defp virtual_flag_width(2), do: 6.0
  defp virtual_flag_width(width) when is_number(width), do: max(width * 1.0, 5.0)

  defp horizontal_sway(anim_time, strip_width) do
    amount = sway_amount(strip_width)

    :math.sin(anim_time * 0.55) * amount +
      :math.sin(anim_time * 0.21 + 1.1) * amount * 0.45
  end

  defp sway_amount(1), do: 0.85
  defp sway_amount(2), do: 1.0
  defp sway_amount(_), do: 0.35

  defp mix_rgb({r1, g1, b1}, {r2, g2, b2}, mix) do
    mix = clamp01(mix)

    {
      trunc(r1 + (r2 - r1) * mix),
      trunc(g1 + (g2 - g1) * mix),
      trunc(b1 + (b2 - b1) * mix)
    }
  end

  defp scale_color({r, g, b}, factor) do
    {
      r |> Kernel.*(factor) |> trunc() |> max(0) |> min(255),
      g |> Kernel.*(factor) |> trunc() |> max(0) |> min(255),
      b |> Kernel.*(factor) |> trunc() |> max(0) |> min(255)
    }
  end

  defp coerce_flag(flag) when flag in @known_flags, do: flag

  defp coerce_flag(flag) when is_binary(flag) do
    case Enum.find(@flag_options, fn {atom, _} -> Atom.to_string(atom) == flag end) do
      {atom, _} -> atom
      nil -> :argentina
    end
  end

  defp coerce_flag(_), do: :argentina

  defp coerce_bool(true), do: true
  defp coerce_bool(false), do: false
  defp coerce_bool("true"), do: true
  defp coerce_bool("false"), do: false
  defp coerce_bool(_), do: false

  defp flag_label(flag) do
    case Enum.find(@flag_options, fn {atom, _} -> atom == coerce_flag(flag) end) do
      {_, label} -> label
      nil -> "Argentina"
    end
  end

  defp format_num(value) when is_number(value), do: :erlang.float_to_binary(value * 1.0, decimals: 1)

  defp clamp_float(value, min, max) when is_number(value) do
    value |> max(min) |> min(max) |> Kernel.*(1.0)
  end

  defp clamp_int(value, min, max) when is_number(value) do
    value |> trunc() |> max(min) |> min(max)
  end

  defp clamp01(value) when value < 0, do: 0.0
  defp clamp01(value) when value > 1, do: 1.0
  defp clamp01(value), do: value
end
