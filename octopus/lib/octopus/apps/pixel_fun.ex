defmodule Octopus.Apps.PixelFun do
  use Octopus.App, category: :interactive
  use Octopus.Params, prefix: :pixelfun

  alias Octopus.Canvas
  alias Octopus.Events.Event.Audio, as: AudioEvent
  alias Octopus.Events.Event.Input, as: InputEvent
  alias Octopus.Events.Event.Proximity, as: ProximityEvent
  alias Octopus.AppSupervisor
  alias Octopus.Apps.PixelFun.Program
  alias Octopus.Installation

  @app_mode_presets "Elixir.Octopus.AppModePresets"

  @default_scene %{
    color_mode: :random,
    saturation_percent: 70,
    color_interval: 5.0,
    translate_scale: 0.0,
    rotate_scale: 0.0,
    zoom_scale: 1.0,
    sway_scale: 0.0,
    sway_speed: 0.5,
    sway_mode: :wobble,
    time_direction: :forward
  }

  @sway_defaults %{sway_scale: 0.0, sway_speed: 0.5, sway_mode: :wobble}

  @builtin_scene_keys [
    :color_mode,
    :saturation_percent,
    :color_interval,
    :translate_scale,
    :rotate_scale,
    :zoom_scale,
    :sway_scale,
    :sway_speed,
    :sway_mode,
    :time_direction
  ]

  @builtin_defs [
    %{
      slug: "classic_ripple",
      name: "Classic ripple",
      formula: "sin(10*t-hypot(x,y))",
      accent_color: "#E74C3C"
    },
    %{
      slug: "cross_waves",
      name: "Cross waves",
      formula: "sin(x*0.7+t*2)*cos(y*0.7+t*1.3)",
      accent_color: "#3498DB"
    },
    %{
      slug: "xy_interference",
      name: "XY interference",
      formula: "sin(x*y*0.08)*cos(t*3)",
      accent_color: "#9B59B6"
    },
    %{
      slug: "nested_sincos",
      name: "Nested sin/cos",
      formula: "sin(x*0.4+sin(y*0.3+t)*3+t)*cos(y*0.4+cos(x*0.3+t)*3+t)",
      accent_color: "#1ABC9C"
    },
    %{
      slug: "layered_waves",
      name: "Layered waves",
      formula: "sin(x*0.5+t)*cos(y*0.5+t)+sin((x+y)*0.35+t*1.5)*0.5",
      accent_color: "#F39C12"
    },
    %{
      slug: "ripple_rings",
      name: "Ripple rings",
      formula: "sin(hypot(x,y)*5-t*3)*sin(hypot(x+3,y+3)*5+t*2)",
      accent_color: "#E91E63"
    },
    %{
      slug: "organic_swirl",
      name: "Organic swirl",
      formula: "sin(x*y*0.06+sin(t)*x*0.2-t*2)*cos(hypot(x,y)*2+t)",
      accent_color: "#2ECC71"
    },
    %{
      slug: "swaytest",
      name: "Swaytest",
      formula: "(tanh((y-0.3)*4)+tanh((y+0.3)*4))/2",
      accent_color: "#FF7043",
      zoom_scale: 0.0
    }
  ]

  @fps 60
  @frame_time_ms trunc(1000 / @fps)
  @min_white_level_gap 30
  @min_white_level 32

  defmodule State do
    defstruct [
      :program,
      :source,
      :colors,
      :last_colors,
      :target_colors,
      :lerp_time,
      :translate_scale,
      :rotate_scale,
      :zoom_scale,
      :sway_scale,
      :sway_speed,
      :sway_mode,
      :time_direction,
      :color_mode,
      :saturation_percent,
      :color_interval,
      # Id of the scene currently rendered on the wall.
      :live_scene_id,
      :offset,
      :move,
      :audio_input,
      :seconds,
      :buttons,
      :panel_interaction_factors,
      :panel_proximities,
      :speed,
      :display_info,
      :color_timer_ref
    ]
  end

  def name(), do: "Pixel Fun"

  def compatible?() do
    Octopus.App.get_installation_info().panel_count >= 1
  end

  def config_schema() do
    %{
      program: {"Formula", :string, %{default: "sin(10*t-hypot(x,y))"}},
      color_mode: {"Colors", :atom, %{default: :random}},
      saturation_percent: {"Saturation", :int, %{default: 70, min: 0, max: 100}},
      color_interval:
        {"Palette crossfade (s)", :float, %{default: 5, min: 1, max: 20, step: 0.5}},
      translate_scale: {"Drift strength", :float, %{default: 0.0, min: 0, max: 20, step: 0.1}},
      rotate_scale: {"Rotation speed", :float, %{default: 0.0, min: -4, max: 4, step: 0.01}},
      zoom_scale: {"Zoom pulse strength", :float, %{default: 1.0, min: 0, max: 10, step: 0.1}},
      sway_scale: {"Sway strength", :float, %{default: 0.0, min: 0, max: 4, step: 0.1}},
      sway_speed: {"Sway speed", :float, %{default: 0.5, min: 0, max: 3, step: 0.05}},
      sway_mode:
        {"Sway mode", :select,
         %{
           default: 0,
           options: [{"Wobble", :wobble}, {"Pendulum", :pendulum}]
         }},
      time_direction:
        {"Time direction", :select,
         %{
           default: 0,
           options: [{"Forward", :forward}, {"Backward", :backward}]
         }}
    }
  end

  def config_info(_config) do
    """
    Pixel Fun draws a math formula per pixel. Result −1…1 controls brightness; zero renders black. Random dual mode maps positive/negative lobes to two palette colours; Rainbow mode derives hue from pattern coordinates so the full spectrum is visible at once.

    Formula — expression evaluated per pixel. Pick a scene preset tile or type your own; saved scenes persist across restarts. Variables: x, y (position), t (time, scaled by global Speed), i (pixel index), l/m/h (audio bass/mid/high if present), pi, tau.

    Colors — Random dual crossfades between random colour pairs; Rainbow spreads hue across the pattern (moves with drift/rotation). White dual maps positive/negative lobes to two brightness levels on the warm W channel of the TM1814 LEDs (no RGB tint). Palette crossfade applies in Random dual and White dual modes.

    Saturation — colour vividness for Random dual and Rainbow (0 = grey, 100 = full; default 70). White dual ignores saturation.

    Drift strength — automatic sin/cos panning of the pattern (0 = off). Not manual translation.

    Rotation speed — 2D spin around the pattern centre (~1 revolution every 6 s at 1.0, using ring width as scale on circular layouts). 0 = off. Negative values reverse direction.

    Time direction — forward (default) or backward. Backward reverses formula animation, rotation, sway, and drift together. Palette crossfade is unaffected.

    Zoom pulse strength — vertical breathing; actual zoom oscillates between ~0 and this value on the y axis only (0 forces zoom 1×).

    Sway strength — tilting-platform wobble in y, sinusoidal around the ring (0 = off). Wobble travels the low point; Pendulum oscillates tilt amplitude.

    Scenes — pick a scene to play it on the wall. Add scenes to the queue to rotate through them at the chosen interval.
    """
  end

  def get_config(state) do
    scene = %{
      program: state.source,
      color_mode: state.color_mode,
      saturation_percent: state.saturation_percent,
      color_interval: state.color_interval,
      translate_scale: state.translate_scale,
      rotate_scale: state.rotate_scale,
      zoom_scale: state.zoom_scale,
      sway_scale: state.sway_scale,
      sway_speed: state.sway_speed,
      sway_mode: state.sway_mode,
      time_direction: state.time_direction
    }

    Map.merge(scene, %{
      live_scene_id: live_scene_id(state, scene),
      active_preset_id: running_preset_id(state, scene)
    })
  end

  def list_modes do
    presets().list_modes(__MODULE__)
  end

  def mode_config(mode_id) do
    presets().config_for(__MODULE__, mode_id) || %{}
  end

  def builtin_presets do
    Enum.map(@builtin_defs, fn def ->
      %{
        slug: def.slug,
        name: def.name,
        accent_color: def.accent_color,
        config: builtin_config(def)
      }
    end)
  end

  def legacy_mode_config(slug) do
    case Enum.find(@builtin_defs, &(&1.slug == slug)) do
      nil -> %{}
      def -> builtin_config(def)
    end
  end

  def summary_for_preset(%{config: config}) do
    sway =
      if (config[:sway_scale] || 0) > 0 do
        " · sway #{format_num(config[:sway_scale])}"
      else
        ""
      end

    color_mode = Map.get(config, :color_mode, :random)

    palette =
      case color_mode do
        :rainbow -> "rainbow"
        :white -> "white #{format_num(config[:color_interval])}s"
        _ -> "palette #{format_num(config[:color_interval])}s"
      end

    sliders =
      "drift #{format_num(config[:translate_scale])} · rot #{format_num(config[:rotate_scale])} · zoom #{format_num(config[:zoom_scale])} · #{palette}#{sway}"

    formula =
      (config[:program] || "")
      |> String.trim()
      |> then(fn f -> if String.length(f) > 28, do: String.slice(f, 0, 25) <> "...", else: f end)

    "#{sliders} · #{formula}"
  end

  defp format_num(n) when is_float(n), do: :erlang.float_to_binary(n, decimals: 1)
  defp format_num(n) when is_integer(n), do: Integer.to_string(n)
  defp format_num(n), do: to_string(n)

  def mode_tweakables(_mode_id) do
    [
      %{
        key: :program,
        label: "Formula",
        type: :formula,
        default: "sin(10*t-hypot(x,y))",
        hint: "x y t i · l m h · pi PI tau"
      },
      %{
        key: :color_mode,
        label: "Colors",
        type: :choice,
        default: :random,
        options: [{:random, "Random dual"}, {:rainbow, "Rainbow"}, {:white, "White dual (W channel)"}]
      },
      %{
        key: :saturation_percent,
        label: "Saturation",
        type: :slider,
        min: 0,
        max: 100,
        step: 1,
        default: 70,
        visible_when: {:color_mode, [:random, :rainbow]}
      },
      %{
        key: :color_interval,
        label: "Palette crossfade",
        type: :slider,
        min: 1.0,
        max: 20.0,
        step: 0.5,
        unit: "s",
        default: 5.0
      },
      %{
        key: :translate_scale,
        label: "Drift",
        type: :slider,
        min: 0.0,
        max: 20.0,
        step: 0.1,
        default: 0.0
      },
      %{
        key: :rotate_scale,
        label: "Rotation",
        type: :slider,
        min: -4.0,
        max: 4.0,
        step: 0.01,
        default: 0.0
      },
      %{
        key: :zoom_scale,
        label: "Zoom pulse",
        type: :slider,
        min: 0.0,
        max: 10.0,
        step: 0.1,
        default: 1.0
      },
      %{
        key: :sway_scale,
        label: "Sway strength",
        type: :slider,
        min: 0.0,
        max: 4.0,
        step: 0.1,
        default: 0.0
      },
      %{
        key: :sway_speed,
        label: "Sway speed",
        type: :slider,
        min: 0.0,
        max: 3.0,
        step: 0.05,
        default: 0.5
      },
      %{
        key: :sway_mode,
        label: "Sway mode",
        type: :select,
        options: [{"Wobble", :wobble}, {"Pendulum", :pendulum}],
        default: :wobble
      },
      %{
        key: :time_direction,
        label: "Time direction",
        type: :select,
        options: [{"Forward", :forward}, {"Backward", :backward}],
        default: :forward
      }
    ]
  end

  def apply_mode(app_id, mode_id) do
    cast(app_id, {:apply_mode, to_string(mode_id)})
  end

  def app_init(config) do
    Octopus.App.configure_display(layout: :gapped_panels, supports_grayscale: true)
    Octopus.App.subscribe_to_button_events()
    Octopus.Params.Global.subscribe()

    display_info = Octopus.App.get_display_info()
    config = coerce_config(config)

    {:ok, program} = config.program |> Program.parse()

    :timer.send_interval(@frame_time_ms, :tick)
    color_mode = Map.get(config, :color_mode, :random)
    saturation_percent = Map.get(config, :saturation_percent, 70)
    palette = generate_random_palette(color_mode, saturation_percent)
    color_timer_ref = maybe_start_color_timer(color_mode, config.color_interval, nil)

    {seconds, micros} = NaiveDateTime.utc_now() |> NaiveDateTime.to_gregorian_seconds()
    seconds = seconds + micros / 1_000_000

    panel_interaction_factors =
      0..(Installation.num_panels() - 1) |> Enum.map(fn i -> {i, 0.0} end) |> Map.new()

    state = %State{
      program: program,
      source: config.program,
      colors: palette,
      last_colors: palette,
      target_colors: palette,
      lerp_time: config.color_interval,
      color_mode: color_mode,
      saturation_percent: saturation_percent,
      color_interval: config.color_interval,
      translate_scale: config.translate_scale,
      rotate_scale: config.rotate_scale,
      zoom_scale: config.zoom_scale,
      sway_scale: Map.get(config, :sway_scale, @sway_defaults.sway_scale),
      sway_speed: Map.get(config, :sway_speed, @sway_defaults.sway_speed),
      sway_mode: config |> Map.get(:sway_mode, @sway_defaults.sway_mode) |> Octopus.Sway.normalize_mode(),
      time_direction: config |> Map.get(:time_direction, :forward) |> coerce_time_direction(),
      live_scene_id: scene_presets().id_for_config(config),
      offset: {0, 0},
      move: {0, 0},
      audio_input: %{low: 0.0, mid: 0.0, high: 0.0},
      seconds: seconds,
      buttons: %{},
      panel_interaction_factors: panel_interaction_factors,
      panel_proximities: Map.new(0..(Installation.num_panels() - 1), fn i -> {i, 0.0} end),
      speed: Octopus.Params.Global.speed(),
      display_info: display_info,
      color_timer_ref: color_timer_ref
    }

    {:ok, state}
  end

  def handle_config(config, %State{} = state) do
    state = apply_scene_fields(state, config)
    broadcast_config(state)
    {:noreply, state}
  end

  defp cast(app_id, message) do
    case AppSupervisor.lookup_app(app_id) do
      {pid, _module} -> GenServer.cast(pid, message)
      _ -> :ok
    end
  end

  def update_program(pid, program) do
    program =
      case Program.parse(program) do
        {:ok, program} -> program
        _ -> 0
      end

    GenServer.cast(pid, {:update_program, program})
  end

  def handle_cast({:update_program, program}, %State{} = state) do
    {:noreply, %{state | program: program}}
  end

  def handle_cast({:apply_mode, scene_id}, %State{} = state) do
    state = apply_scene_by_id(state, scene_id)
    state = %State{state | live_scene_id: scene_id}
    broadcast_config(state)
    {:noreply, state}
  end

  defp apply_scene_fields(%State{} = state, config) do
    config = coerce_config(config)
    program_source = Map.get(config, :program, state.source)

    program =
      case Program.parse(program_source) do
        {:ok, program} -> program
        _ -> state.program
      end

    old_color_interval = state.color_interval
    old_color_mode = state.color_mode
    color_interval = Map.get(config, :color_interval, old_color_interval)
    color_mode = Map.get(config, :color_mode, old_color_mode)
    saturation_percent = Map.get(config, :saturation_percent, state.saturation_percent || 70)

    state = %State{
      state
      | program: program,
        source: program_source,
        translate_scale: Map.get(config, :translate_scale, state.translate_scale),
        rotate_scale: Map.get(config, :rotate_scale, state.rotate_scale),
        zoom_scale: Map.get(config, :zoom_scale, state.zoom_scale),
        sway_scale: Map.get(config, :sway_scale, state.sway_scale),
        sway_speed: Map.get(config, :sway_speed, state.sway_speed),
        sway_mode:
          config
          |> Map.get(:sway_mode, state.sway_mode)
          |> Octopus.Sway.normalize_mode(),
        time_direction:
          config
          |> Map.get(:time_direction, state.time_direction || :forward)
          |> coerce_time_direction(),
        color_mode: color_mode,
        saturation_percent: saturation_percent,
        color_interval: color_interval
    }

    state =
      cond do
        color_mode != old_color_mode ->
          palette = generate_random_palette(color_mode, saturation_percent)
          color_timer_ref = maybe_start_color_timer(color_mode, color_interval, state.color_timer_ref)

          %State{
            state
            | colors: palette,
              last_colors: palette,
              target_colors: palette,
              color_timer_ref: color_timer_ref,
              lerp_time: color_interval_s(state)
          }

        color_mode in [:random, :white] and color_interval != old_color_interval ->
          state = reschedule_color_timer(state)
          %State{state | lerp_time: color_interval_s(state)}

        true ->
          state
      end

    state
  end

  defp maybe_start_color_timer(color_mode, color_interval, existing_ref)
       when color_mode in [:random, :white] do
    if existing_ref, do: Process.cancel_timer(existing_ref)
    Process.send_after(self(), :update_colors, color_interval_ms(color_interval))
  end

  defp maybe_start_color_timer(_color_mode, _color_interval, existing_ref) do
    if existing_ref, do: Process.cancel_timer(existing_ref)
    nil
  end

  defp coerce_config(config) when is_map(config) do
    Map.new(config, fn
      {:color_mode, value} -> {:color_mode, coerce_color_mode(value)}
      {:saturation_percent, value} -> {:saturation_percent, coerce_saturation_percent(value)}
      {:time_direction, value} -> {:time_direction, coerce_time_direction(value)}
      {key, value} -> {key, value}
    end)
  end

  defp coerce_color_mode(value) when is_atom(value), do: value

  defp coerce_color_mode(value) when is_binary(value) do
    case value do
      "random" -> :random
      "rainbow" -> :rainbow
      "white" -> :white
      _ -> :random
    end
  end

  defp coerce_color_mode(_), do: :random

  defp coerce_saturation_percent(value) when is_integer(value), do: value |> max(0) |> min(100)

  defp coerce_saturation_percent(value) when is_float(value),
    do: value |> trunc() |> coerce_saturation_percent()

  defp coerce_saturation_percent(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, _} -> coerce_saturation_percent(n)
      :error -> 70
    end
  end

  defp coerce_saturation_percent(_), do: 70

  defp coerce_time_direction(value) when value in [:forward, :backward], do: value

  defp coerce_time_direction("forward"), do: :forward
  defp coerce_time_direction("backward"), do: :backward
  defp coerce_time_direction(_), do: :forward

  defp time_sign(:backward), do: -1
  defp time_sign(_), do: 1

  defp effective_seconds(%State{} = state), do: state.seconds * time_sign(state.time_direction)

  defp reschedule_color_timer(%State{color_mode: color_mode} = state)
       when color_mode in [:random, :white] do
    if ref = state.color_timer_ref do
      Process.cancel_timer(ref)
    end

    ref = Process.send_after(self(), :update_colors, color_interval_ms(state.color_interval))
    %State{state | color_timer_ref: ref}
  end

  defp reschedule_color_timer(%State{} = state), do: state

  defp apply_scene_by_id(%State{} = state, scene_id) do
    mod = scene_presets()

    case apply(mod, :get, [scene_id]) do
      nil -> state
      preset -> apply_scene_fields(state, apply(mod, :to_config, [preset]))
    end
  end

  defp broadcast_config(%State{} = state) do
    case AppSupervisor.lookup_app_id(self()) do
      nil ->
        :ok

      app_id ->
        Phoenix.PubSub.broadcast(
          Octopus.PubSub,
          "apps",
          {:apps, {:config_updated, app_id, get_config(state)}}
        )
    end
  end

  # Id of the scene currently on the wall. Prefers the explicitly tracked id
  # (set whenever a scene is loaded) and falls back to an exact scene match.
  defp live_scene_id(%State{live_scene_id: id}, _scene) when is_binary(id), do: id
  defp live_scene_id(_state, scene), do: scene_presets().id_for_config(scene)

  defp running_preset_id(%State{live_scene_id: id}, _scene) when is_binary(id), do: id
  defp running_preset_id(_state, scene), do: scene_presets().id_for_config(scene)

  defp scene_presets, do: String.to_existing_atom("Elixir.Octopus.Apps.PixelFun.ScenePresets")

  defp presets, do: String.to_existing_atom(@app_mode_presets)

  defp builtin_config(def) do
    @default_scene
    |> Map.put(:program, def.formula)
    |> Map.merge(Map.take(def, @builtin_scene_keys))
  end

  defp color_interval_s(%State{} = state), do: color_interval_ms(state.color_interval) / 1000.0
  defp color_interval_ms(interval) when is_number(interval), do: max(trunc(interval * 1000), 1)

  def handle_info(:update_colors, %State{color_mode: color_mode} = state)
      when color_mode in [:random, :white] do
    colors = generate_random_palette(color_mode, state.saturation_percent)
    color_timer_ref = Process.send_after(self(), :update_colors, color_interval_ms(state.color_interval))

    {:noreply,
     %State{
       state
       | last_colors: state.colors,
         target_colors: colors,
         lerp_time: color_interval_s(state),
         color_timer_ref: color_timer_ref
     }}
  end

  def handle_info(:update_colors, %State{} = state), do: {:noreply, state}

  def handle_info({:param_updated, :speed, new_value}, %State{} = state) do
    {:noreply, %{state | speed: new_value}}
  end

  def handle_info({:param_updated, _key, _value}, %State{} = state) do
    {:noreply, state}
  end

  def handle_info(:tick, %State{} = state) do
    state = lerp_toward_target_colors(state)

    {offset_x, offset_y} = state.offset

    panel_interaction_factors =
      Map.new(state.panel_interaction_factors, fn {i, value} ->
        target = if Map.get(state.buttons, i, false), do: 1.0, else: 0.0
        value = lerp(value, target, 0.05)
        {i, value}
      end)

    state = %State{
      state
      | offset: {offset_x, offset_y},
        seconds: state.seconds + 1 / @fps * param(:time_scale, 1.0) * state.speed,
        panel_interaction_factors: panel_interaction_factors
    }

    canvas = state |> render()
    easing_interval = trunc(param(:easing_interval, 200))

    case state.color_mode do
      :white ->
        Octopus.App.update_display(canvas, :grayscale, easing_interval: easing_interval)

      _ ->
        Octopus.App.update_display(canvas, :rgb, easing_interval: easing_interval)
    end

    {:noreply, state}
  end

  def handle_event(%AudioEvent{bass: low, mid: mid, high: high}, %State{} = state) do
    {:noreply, %State{state | audio_input: %{low: low, mid: mid, high: high}}}
  end

  def handle_event(
        %InputEvent{type: :button} = event,
        %State{} = state
      ) do
    pressed = event.action == :press
    {:noreply, %State{state | buttons: Map.put(state.buttons, event.button - 1, pressed)}}
  end

  def handle_event(%ProximityEvent{panel: panel} = event, %State{} = state) do
    distance = event.distance_combined
    distance_normalized = 1.0 - max(min(distance / 2500.0, 1.0), 0.0)

    panel_proximities =
      Map.update(
        state.panel_proximities,
        panel - 1,
        distance_normalized,
        &lerp(&1, distance_normalized, 0.5)
      )

    {:noreply, %State{state | panel_proximities: panel_proximities}}
  end

  def handle_event(_event, %State{} = state) do
    {:noreply, state}
  end

  @doc false
  def build_canvas(%State{} = state), do: render_canvas(state)

  defp render(%State{} = state), do: render_canvas(state)

  defp render_canvas(%State{display_info: display_info} = state) do
    {offset_x, offset_y} = translate_offset(state)
    zoom = zoom_factor(state)
    seconds = effective_seconds(state)

    transform_params = %{
      offset_x: offset_x,
      offset_y: offset_y,
      zoom: zoom,
      seconds: seconds,
      rotate_scale: state.rotate_scale,
      sway_scale: state.sway_scale || 0.0,
      sway_speed: state.sway_speed || @sway_defaults.sway_speed,
      sway_mode: state.sway_mode || @sway_defaults.sway_mode
    }

    canvas_mode = if state.color_mode == :white, do: :grayscale, else: :rgb
    canvas = Canvas.new(display_info.width, display_info.height, canvas_mode)
    saturation_percent = state.saturation_percent || 70

    lerp_fn = fn a, b, v ->
      interpolate_colors_with_black(a, b, v, saturation_percent)
    end

    Installation.virtual_pixel_positions_per_panel()
    |> Enum.with_index()
    |> Enum.reduce(canvas, fn {panel, index}, canvas ->
      proximity = Map.get(state.panel_proximities, index, 0.0)
      hue_shift = proximity * 180 * 5
      interaction_factor = Map.get(state.panel_interaction_factors, index, 0.0)

      pixel_time = seconds + interaction_factor * 5
      audio = state.audio_input

      Enum.reduce(Enum.with_index(panel), canvas, fn {{x, y}, i}, canvas ->
        {x_scaled, y_scaled} = transform_pixel_coords(x, y, transform_params)

        pixel =
          case state.color_mode do
            :white ->
              {color_a, color_b} = state.colors

              state.program
              |> eval_pixel_value(
                x_scaled,
                y_scaled,
                i,
                pixel_time,
                audio.low,
                audio.mid,
                audio.high
              )
              |> white_pixel_value(color_a, color_b)

            :rainbow ->
              value =
                eval_pixel_value(
                  state.program,
                  x_scaled,
                  y_scaled,
                  i,
                  pixel_time,
                  audio.low,
                  audio.mid,
                  audio.high
                )

              rainbow_pixel_color(x_scaled, y_scaled, value, hue_shift, saturation_percent)

            _ ->
              {color_a, color_b} = state.colors

              colors = {
                %Chameleon.HSV{(%Chameleon.HSV{} = color_a) | h: rem(trunc(color_a.h + hue_shift), 360)},
                %Chameleon.HSV{(%Chameleon.HSV{} = color_b) | h: rem(trunc(color_b.h + hue_shift), 360)}
              }

              pixels(
                state.program,
                x_scaled,
                y_scaled,
                i,
                pixel_time,
                audio.low,
                audio.mid,
                audio.high,
                colors,
                lerp_fn
              )
          end

        Canvas.put_pixel(canvas, {x, y}, pixel)
      end)
    end)
  end

  @doc false
  def transform_pixel_coords(x, y, params) do
    %{
      offset_x: offset_x,
      offset_y: offset_y,
      zoom: zoom,
      seconds: seconds,
      rotate_scale: rotate_scale,
      sway_scale: sway_scale,
      sway_speed: sway_speed,
      sway_mode: sway_mode
    } = params

    w = Installation.width()
    center_x = w / 2 - 0.5
    center_y = Installation.height() / 2 - 0.5

    {x_scaled, y_scaled} =
      rotate_and_zoom(x, y, offset_x, offset_y, center_x, center_y, seconds, rotate_scale, zoom)

    y_final =
      if sway_scale == 0.0 do
        y_scaled
      else
        {sway_amplitude, sway_phase} = Octopus.Sway.params(sway_scale, sway_speed, sway_mode, seconds)
        y_scaled + Octopus.Sway.offset(x, w, sway_amplitude, sway_phase)
      end

    {x_scaled, y_final}
  end

  defp rotate_and_zoom(x, y, offset_x, offset_y, center_x, center_y, seconds, rotate_scale, zoom) do
    rotation = seconds * rotate_scale
    x_translated = x - offset_x - center_x
    y_translated = y - offset_y - center_y

    x_rotated = x_translated * :math.cos(rotation) - y_translated * :math.sin(rotation)
    y_rotated = x_translated * :math.sin(rotation) + y_translated * :math.cos(rotation)

    {x_rotated, y_rotated * zoom}
  end

  @default_env %{
    ~c"pi" => :math.pi(),
    ~c"PI" => :math.pi(),
    ~c"tau" => :math.pi() * 2,
    ~c"Tau" => :math.pi() * 2
  }

  def pixels(expr, x, y, i, t, color_a, color_b, lerp_fn \\ &interpolate_colors_with_black/3)

  def pixels(expr, x, y, i, t, color_a, color_b, lerp_fn)
      when is_binary(expr) do
    {:ok, program} = Program.parse(expr)
    pixels(program, x, y, i, t, color_a, color_b, lerp_fn)
  end

  def pixels(program, x, y, i, t, color_a, color_b, lerp_fn) do
    pixels(program, x, y, i, t, 0, 0, 0, {color_a, color_b}, lerp_fn)
  end

  def pixels(expr, x, y, i, t, l, m, h, {{r1, g1, b1}, {r2, g2, b2}}, lerp_fn) do
    pixels(
      expr,
      x,
      y,
      i,
      t,
      l,
      m,
      h,
      {Chameleon.RGB.new(r1, g1, b1) |> Chameleon.convert(Chameleon.HSV),
       Chameleon.RGB.new(r2, g2, b2) |> Chameleon.convert(Chameleon.HSV)},
      lerp_fn
    )
  end

  def pixels(expr, x, y, i, t, l, m, h, {color_a, color_b}, lerp_fn) do
    env = [
      %{~c"x" => x, ~c"y" => y, ~c"i" => i, ~c"t" => t, ~c"l" => l, ~c"m" => m, ~c"h" => h},
      @default_env
    ]

    value =
      expr
      |> Program.eval(env)
      |> max(-1.0)
      |> min(1.0)

    lerp_fn.(color_a, color_b, value)
  end

  defp eval_pixel_value(expr, x, y, i, t, l, m, h) do
    env = [
      %{~c"x" => x, ~c"y" => y, ~c"i" => i, ~c"t" => t, ~c"l" => l, ~c"m" => m, ~c"h" => h},
      @default_env
    ]

    expr
    |> Program.eval(env)
    |> max(-1.0)
    |> min(1.0)
  end

  defp white_pixel_value(value, %Chameleon.HSV{v: level_a}, %Chameleon.HSV{v: level_b}) do
    level =
      cond do
        value > 0 -> level_a * value
        value < 0 -> level_b * -value
        true -> 0
      end

    level
    |> Kernel.*(param(:value_percent, 100) / 100.0)
    |> Kernel.*(255 / 100.0)
    |> round()
    |> max(0)
    |> min(255)
  end

  defp rainbow_pixel_color(_x, _y, value, _hue_shift, _saturation_percent) when value == 0.0,
    do: {0, 0, 0}

  defp rainbow_pixel_color(x, y, value, hue_shift, saturation_percent) do
    hue = rainbow_hue(x, y, hue_shift)

    saturation = saturation_percent |> max(0) |> min(100)
    brightness = trunc(param(:value_percent, 100) * abs(value)) |> max(0) |> min(100)

    %Chameleon.RGB{r: r, g: g, b: b} =
      Chameleon.HSV.new(hue, saturation, brightness) |> Chameleon.convert(Chameleon.RGB)

    {r, g, b}
  end

  # Spread hue evenly across pattern space (both axes). Pure atan2 clusters
  # two colours on flat/circular layouts where one axis barely varies.
  defp rainbow_hue(x, y, hue_shift) do
    w = max(Installation.width(), 1) * 1.0
    h = max(Installation.height(), 1) * 1.0

    x_frac = (x + w / 2) / w
    y_frac = (y + h / 2) / h

    hue = x_frac * 240.0 + y_frac * 120.0 + hue_shift
    hue = :math.fmod(hue, 360.0)
    hue = if hue < 0, do: hue + 360.0, else: hue

    trunc(hue)
  end

  defp interpolate_colors_with_black(%Chameleon.HSV{} = a, %Chameleon.HSV{} = b, value),
    do: interpolate_colors_with_black(a, b, value, 70)

  defp interpolate_colors_with_black(%Chameleon.HSV{} = a, %Chameleon.HSV{} = b, value, saturation_percent) do
    saturation = saturation_percent |> max(0) |> min(100)

    hsv =
      cond do
        value > 0 ->
          %Chameleon.HSV{
            a
            | s: saturation,
              v: trunc(param(:value_percent, 100) * value) |> max(0) |> min(100)
          }

        value < 0 ->
          %Chameleon.HSV{
            b
            | s: saturation,
              v: trunc(param(:value_percent, 100) * -value) |> max(0) |> min(100)
          }

        true ->
          %Chameleon.HSV{h: 0, s: 0, v: 0}
      end

    hsv = %Chameleon.HSV{hsv | h: hsv.h |> max(0) |> min(359)}

    %Chameleon.RGB{r: r, g: g, b: b} = Chameleon.convert(hsv, Chameleon.RGB)
    {r, g, b}
  end

  defp translate_offset(%State{translate_scale: scale, offset: {ox, oy}} = state) do
    seconds = effective_seconds(state)
    anim_x = :math.sin(0.3 + seconds * 0.17) * scale
    anim_y = :math.cos(0.7 + seconds * 0.05) * scale
    {ox + anim_x, oy + anim_y}
  end

  defp zoom_factor(%State{zoom_scale: zoom}) when zoom == 0, do: 1.0

  defp zoom_factor(%State{} = state) do
    seconds = effective_seconds(state)
    (:math.sin(seconds * 0.1) * 0.5 + 0.5) * state.zoom_scale
  end

  defp lerp_toward_target_colors(%State{color_mode: color_mode} = state)
       when color_mode in [:random, :white] do
    current_time = max(color_interval_s(state) - state.lerp_time, 0)
    t = current_time / color_interval_s(state)
    lerp_time = max(state.lerp_time - 1 / @fps, 0)

    {last_a, last_b} = state.last_colors
    {target_a, target_b} = state.target_colors
    new_a = lerp_rgb(last_a, target_a, t)
    new_b = lerp_rgb(last_b, target_b, t)

    %State{state | colors: {new_a, new_b}, lerp_time: lerp_time}
  end

  defp lerp_toward_target_colors(%State{} = state), do: state

  defp lerp_rgb(a, b, value) do
    a_rgb = Chameleon.convert(a, Chameleon.RGB)
    b_rgb = Chameleon.convert(b, Chameleon.RGB)

    r = lerp(a_rgb.r, b_rgb.r, value) |> trunc()
    g = lerp(a_rgb.g, b_rgb.g, value) |> trunc()
    b = lerp(a_rgb.b, b_rgb.b, value) |> trunc()

    Chameleon.RGB.new(r, g, b)
    |> Chameleon.convert(Chameleon.HSV)
  end

  defp lerp(a, b, t) do
    (1 - t) * a + t * b
  end

  defp generate_random_palette(:white, _saturation_percent), do: generate_random_white_levels()
  defp generate_random_palette(_color_mode, saturation_percent), do: generate_random_colors(saturation_percent)

  @doc false
  def generate_random_white_levels do
    low_max = 100 - @min_white_level_gap
    low = @min_white_level + :rand.uniform(low_max - @min_white_level + 1) - 1
    extra = 100 - low - @min_white_level_gap

    high =
      if extra <= 0 do
        100
      else
        low + @min_white_level_gap + :rand.uniform(extra)
      end

    {a, b} =
      case :rand.uniform(2) do
        1 -> {low, high}
        2 -> {high, low}
      end

    {%Chameleon.HSV{h: 0, s: 0, v: a}, %Chameleon.HSV{h: 0, s: 0, v: b}}
  end

  defp generate_random_colors(saturation_percent) do
    hue_a = :rand.uniform(360) - 1
    hue_b = Integer.mod(hue_a + 60 + :rand.uniform(180) - 1, 360)
    sat = saturation_percent |> max(0) |> min(100)
    hsv_a = Chameleon.HSV.new(hue_a, sat, 100)
    hsv_b = Chameleon.HSV.new(hue_b, sat, 100)
    {hsv_a, hsv_b}
  end
end
