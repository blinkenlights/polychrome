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
    color_interval: 5.0,
    translate_scale: 0.0,
    rotate_scale: 0.0,
    zoom_scale: 1.0
  }

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
      formula: "sin(x*0.7+t*2)*cos(y*0.7-t*1.3)",
      accent_color: "#3498DB"
    },
    %{
      slug: "xy_interference",
      name: "XY interference",
      formula: "sin(x*y*0.08 - t*3)",
      accent_color: "#9B59B6"
    },
    %{
      slug: "nested_sincos",
      name: "Nested sin/cos",
      formula: "sin(x*0.4+sin(y*0.3+t)*3+t)*cos(y*0.4+cos(x*0.3-t)*3-t)",
      accent_color: "#1ABC9C"
    },
    %{
      slug: "layered_waves",
      name: "Layered waves",
      formula: "sin(x*0.5+t)*cos(y*0.5-t)+sin((x+y)*0.35+t*1.5)*0.5",
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
    }
  ]

  @fps 60
  @frame_time_ms trunc(1000 / @fps)

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
      color_interval:
        {"Palette crossfade (s)", :float, %{default: 5, min: 1, max: 20, step: 0.5}},
      translate_scale: {"Drift strength", :float, %{default: 0.0, min: 0, max: 20, step: 0.1}},
      rotate_scale: {"Rotation speed", :float, %{default: 0.0, min: 0, max: 4, step: 0.01}},
      zoom_scale: {"Zoom pulse strength", :float, %{default: 1.0, min: 0, max: 10, step: 0.1}}
    }
  end

  def config_info(_config) do
    """
    Pixel Fun draws a math formula per pixel. Result −1…1 maps to two palette colours; zero renders black.

    Formula — expression evaluated per pixel. Pick a scene preset tile or type your own; saved scenes persist across restarts. Variables: x, y (position), t (time, scaled by global Speed), i (pixel index), l/m/h (audio bass/mid/high if present), pi, tau.

    Palette crossfade — seconds between new random colour pairs; the transition is smooth over the same duration.

    Drift strength — automatic sin/cos panning of the pattern (0 = off). Not manual translation.

    Rotation speed — spin rate around the installation centre (0 = off).

    Zoom pulse strength — breathing zoom; actual zoom oscillates between ~0 and this value (0 forces zoom 1×).

    Scenes — pick a scene to play it on the wall. Add scenes to the queue to rotate through them at the chosen interval.
    """
  end

  def get_config(state) do
    scene = %{
      program: state.source,
      color_interval: state.color_interval,
      translate_scale: state.translate_scale,
      rotate_scale: state.rotate_scale,
      zoom_scale: state.zoom_scale
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
      config =
        @default_scene
        |> Map.put(:program, def.formula)

      %{
        slug: def.slug,
        name: def.name,
        accent_color: def.accent_color,
        config: config
      }
    end)
  end

  def legacy_mode_config(slug) do
    case Enum.find(@builtin_defs, &(&1.slug == slug)) do
      nil ->
        %{}

      def ->
        @default_scene
        |> Map.put(:program, def.formula)
    end
  end

  def summary_for_preset(%{config: config}) do
    sliders =
      "drift #{format_num(config[:translate_scale])} · rot #{format_num(config[:rotate_scale])} · zoom #{format_num(config[:zoom_scale])} · palette #{format_num(config[:color_interval])}s"

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
        hint: "x y t i · l m h · pi tau"
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
        min: 0.0,
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
      }
    ]
  end

  def apply_mode(app_id, mode_id) do
    cast(app_id, {:apply_mode, to_string(mode_id)})
  end

  def app_init(config) do
    Octopus.App.configure_display(layout: :gapped_panels)
    Octopus.App.subscribe_to_button_events()
    Octopus.Params.Global.subscribe()

    display_info = Octopus.App.get_display_info()

    {:ok, program} = config.program |> Program.parse()

    :timer.send_interval(@frame_time_ms, :tick)
    color_timer_ref = Process.send_after(self(), :update_colors, color_interval_ms(config.color_interval))

    {seconds, micros} = NaiveDateTime.utc_now() |> NaiveDateTime.to_gregorian_seconds()
    seconds = seconds + micros / 1_000_000

    panel_interaction_factors =
      0..(Installation.num_panels() - 1) |> Enum.map(fn i -> {i, 0.0} end) |> Map.new()

    state = %State{
      program: program,
      source: config.program,
      colors: generate_random_colors(),
      last_colors: generate_random_colors(),
      target_colors: generate_random_colors(),
      lerp_time: config.color_interval,
      color_interval: config.color_interval,
      translate_scale: config.translate_scale,
      rotate_scale: config.rotate_scale,
      zoom_scale: config.zoom_scale,
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
    program_source = Map.get(config, :program, state.source)

    program =
      case Program.parse(program_source) do
        {:ok, program} -> program
        _ -> state.program
      end

    old_color_interval = state.color_interval
    color_interval = Map.get(config, :color_interval, old_color_interval)

    state = %State{
      state
      | program: program,
        source: program_source,
        translate_scale: Map.get(config, :translate_scale, state.translate_scale),
        rotate_scale: Map.get(config, :rotate_scale, state.rotate_scale),
        zoom_scale: Map.get(config, :zoom_scale, state.zoom_scale),
        color_interval: color_interval
    }

    if color_interval != old_color_interval do
      state = reschedule_color_timer(state)
      %State{state | lerp_time: color_interval_s(state)}
    else
      state
    end
  end

  defp reschedule_color_timer(%State{} = state) do
    if ref = state.color_timer_ref do
      Process.cancel_timer(ref)
    end

    ref = Process.send_after(self(), :update_colors, color_interval_ms(state.color_interval))
    %State{state | color_timer_ref: ref}
  end

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

  defp color_interval_s(%State{} = state), do: color_interval_ms(state.color_interval) / 1000.0
  defp color_interval_ms(interval) when is_number(interval), do: max(trunc(interval * 1000), 1)

  def handle_info(:update_colors, %State{} = state) do
    colors = generate_random_colors()
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

    # Use new unified display API with dynamic easing_interval parameter
    Octopus.App.update_display(canvas, :rgb, easing_interval: trunc(param(:easing_interval, 200)))

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
    rotation = state.seconds * state.rotate_scale

    center_x = Installation.width() / 2 - 0.5
    center_y = Installation.height() / 2 - 0.5

    canvas = Canvas.new(display_info.width, display_info.height)

    Installation.virtual_pixel_positions_per_panel()
    |> Enum.with_index()
    |> Enum.reduce(canvas, fn {panel, index}, canvas ->
      proximity = Map.get(state.panel_proximities, index, 0.0)
      hue_shift = proximity * 180 * 5
      interaction_factor = Map.get(state.panel_interaction_factors, index, 0.0)

      {color_a, color_b} = state.colors

      colors = {
        %Chameleon.HSV{(%Chameleon.HSV{} = color_a) | h: rem(trunc(color_a.h + hue_shift), 360)},
        %Chameleon.HSV{(%Chameleon.HSV{} = color_b) | h: rem(trunc(color_b.h + hue_shift), 360)}
      }

      Enum.reduce(Enum.with_index(panel), canvas, fn {{x, y}, i}, canvas ->
        x_translated = x - offset_x - center_x
        y_translated = y - offset_y - center_y

        x_rotated = x_translated * :math.cos(rotation) - y_translated * :math.sin(rotation)
        y_rotated = x_translated * :math.sin(rotation) + y_translated * :math.cos(rotation)

        x_scaled = x_rotated * zoom
        y_scaled = y_rotated * zoom

        color =
          pixels(
            state.program,
            x_scaled,
            y_scaled,
            i,
            state.seconds + interaction_factor * 5,
            state.audio_input.low,
            state.audio_input.mid,
            state.audio_input.high,
            colors,
            &interpolate_colors_with_black/3
          )

        Canvas.put_pixel(canvas, {x, y}, color)
      end)
    end)
  end

  @default_env %{~c"pi" => :math.pi(), ~c"tau" => :math.pi() * 2}

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

  defp interpolate_colors_with_black(%Chameleon.HSV{} = a, %Chameleon.HSV{} = b, value) do
    hsv =
      cond do
        value > 0 ->
          %Chameleon.HSV{
            a
            | s: param(:saturation_percent, 70) |> max(0) |> min(100),
              v: trunc(param(:value_percent, 100) * value) |> max(0) |> min(100)
          }

        value < 0 ->
          %Chameleon.HSV{
            b
            | s: param(:saturation_percent, 70) |> max(0) |> min(100),
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
    anim_x = :math.sin(0.3 + state.seconds * 0.17) * scale
    anim_y = :math.cos(0.7 + state.seconds * 0.05) * scale
    {ox + anim_x, oy + anim_y}
  end

  defp zoom_factor(%State{zoom_scale: 0}), do: 1.0

  defp zoom_factor(%State{zoom_scale: scale, seconds: seconds}) do
    (:math.sin(seconds * 0.1) * 0.5 + 0.5) * scale
  end

  defp lerp_toward_target_colors(%State{} = state) do
    current_time = max(color_interval_s(state) - state.lerp_time, 0)
    t = current_time / color_interval_s(state)
    lerp_time = max(state.lerp_time - 1 / @fps, 0)

    {last_a, last_b} = state.last_colors
    {target_a, target_b} = state.target_colors
    new_a = lerp_rgb(last_a, target_a, t)
    new_b = lerp_rgb(last_b, target_b, t)

    %State{state | colors: {new_a, new_b}, lerp_time: lerp_time}
  end

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

  defp generate_random_colors do
    hue_a = :rand.uniform(360) - 1
    hue_b = Integer.mod(hue_a + 60 + :rand.uniform(180) - 1, 360)
    sat_a = param(:saturation_percent, 70)
    sat_b = param(:saturation_percent, 70)
    hsv_a = Chameleon.HSV.new(hue_a, sat_a, 100)
    hsv_b = Chameleon.HSV.new(hue_b, sat_b, 100)
    {hsv_a, hsv_b}
  end
end
