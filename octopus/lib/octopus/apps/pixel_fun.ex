defmodule Octopus.Apps.PixelFun do
  use Octopus.App, category: :interactive
  use Octopus.Params, prefix: :pixelfun

  alias Octopus.Canvas
  alias Octopus.Events.Event.Audio, as: AudioEvent
  alias Octopus.Events.Event.Input, as: InputEvent
  alias Octopus.Events.Event.Proximity, as: ProximityEvent
  alias Octopus.Apps.PixelFun.Program
  alias Octopus.Installation

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
      :cycle_functions,
      :cycle_functions_interval,
      :offset,
      :move,
      :audio_input,
      :seconds,
      :buttons,
      :panel_interaction_factors,
      :panel_proximities,
      :speed,
      :display_info
    ]
  end

  def name(), do: "Pixel Fun"

  def compatible?() do
    info = Octopus.App.get_installation_info()

    (info.panel_width == 8 and info.panel_height == 8) or
      info.panel_width == 1 or info.panel_height == 1
  end

  def config_schema() do
    %{
      program:
        {"Formula", :formula_preset,
         %{
           default: "sin(10*t-hypot(x,y))",
           presets_module: Octopus.Apps.PixelFun.FormulaPresets
         }},
      color_interval:
        {"Palette crossfade (s)", :float, %{default: 5, min: 1, max: 20, step: 0.5}},
      translate_scale: {"Drift strength", :float, %{default: 0.0, min: 0, max: 20, step: 0.1}},
      rotate_scale: {"Rotation speed", :float, %{default: 0.0, min: 0, max: 4, step: 0.01}},
      zoom_scale: {"Zoom pulse strength", :float, %{default: 1.0, min: 0, max: 10, step: 0.1}},
      cycle_functions: {"Cycle presets", :boolean, %{default: false}},
      cycle_functions_interval:
        {"Preset interval (s)", :float,
         %{
           default: 30,
           min: 1,
           max: 60 * 60,
           step: 1,
           visible_when: {:cycle_functions, [true]}
         }}
    }
  end

  def config_info(_config) do
    """
    Pixel Fun draws a math formula per pixel. Result −1…1 maps to two palette colours; zero renders black.

    Formula — expression evaluated per pixel. Pick a preset or type your own; saved presets persist across restarts. Variables: x, y (position), t (time, scaled by global Speed), i (pixel index), l/m/h (audio bass/mid/high if present), pi, tau.

    Palette crossfade — seconds between new random colour pairs; the transition is smooth over the same duration.

    Drift strength — automatic sin/cos panning of the pattern (0 = off). Not manual translation.

    Rotation speed — spin rate around the installation centre (0 = off).

    Zoom pulse strength — breathing zoom; actual zoom oscillates between ~0 and this value (0 forces zoom 1×).

    Cycle presets / Preset interval — reserved for rotating through preset formulas (not active yet).
    """
  end

  def get_config(state) do
    %{
      program: state.source,
      color_interval: state.color_interval,
      cycle_functions: state.cycle_functions,
      cycle_functions_interval: state.cycle_functions_interval,
      translate_scale: state.translate_scale,
      rotate_scale: state.rotate_scale,
      zoom_scale: state.zoom_scale
    }
  end

  def app_init(config) do
    Octopus.App.configure_display(layout: :gapped_panels)
    Octopus.App.subscribe_to_button_events()
    Octopus.Params.Global.subscribe()

    display_info = Octopus.App.get_display_info()

    {:ok, program} = config.program |> Program.parse()

    :timer.send_interval(@frame_time_ms, :tick)
    Process.send_after(self(), :update_colors, color_interval_ms(config.color_interval))

    {seconds, micros} = NaiveDateTime.utc_now() |> NaiveDateTime.to_gregorian_seconds()
    seconds = seconds + micros / 1_000_000

    panel_interaction_factors =
      0..(Installation.num_panels() - 1) |> Enum.map(fn i -> {i, 0.0} end) |> Map.new()

    {:ok,
     %State{
       program: program,
       source: config.program,
       colors: generate_random_colors(),
       last_colors: generate_random_colors(),
       target_colors: generate_random_colors(),
       lerp_time: config.color_interval,
       color_interval: config.color_interval,
       cycle_functions: config.cycle_functions,
       cycle_functions_interval: config.cycle_functions_interval,
       translate_scale: config.translate_scale,
       rotate_scale: config.rotate_scale,
       zoom_scale: config.zoom_scale,
       offset: {0, 0},
       move: {0, 0},
       audio_input: %{low: 0.0, mid: 0.0, high: 0.0},
       seconds: seconds,
       buttons: %{},
       panel_interaction_factors: panel_interaction_factors,
       panel_proximities: Map.new(0..(Installation.num_panels() - 1), fn i -> {i, 0.0} end),
       speed: Octopus.Params.Global.speed(),
       display_info: display_info
     }}
  end

  def handle_config(
        %{
          program: program,
          cycle_functions: cycle_functions,
          translate_scale: translate_scale,
          rotate_scale: rotate_scale,
          zoom_scale: zoom_scale
        } = config,
        %State{} = state
      ) do
    source = program

    program =
      case Program.parse(program) do
        {:ok, program} -> program
        _ -> 0
      end

    color_interval = Map.get(config, :color_interval, state.color_interval)

    new_state = %State{
      state
      | program: program,
        source: source,
        cycle_functions: cycle_functions,
        cycle_functions_interval: Map.get(config, :cycle_functions_interval, state.cycle_functions_interval),
        translate_scale: translate_scale,
        rotate_scale: rotate_scale,
        zoom_scale: zoom_scale,
        color_interval: color_interval
    }

    {:noreply, new_state}
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

  defp color_interval_s(%State{} = state), do: color_interval_ms(state.color_interval) / 1000.0
  defp color_interval_ms(interval) when is_number(interval), do: max(trunc(interval * 1000), 1)

  def handle_info(:update_colors, %State{} = state) do
    colors = generate_random_colors()

    Process.send_after(self(), :update_colors, color_interval_ms(state.color_interval))

    {:noreply,
     %State{
       state
       | last_colors: state.colors,
         target_colors: colors,
         lerp_time: color_interval_s(state)
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
    hue_b = Integer.mod(hue_a + 90 + :rand.uniform(180) - 1, 360)
    sat_a = param(:saturation_percent, 70)
    sat_b = param(:saturation_percent, 70)
    hsv_a = Chameleon.HSV.new(hue_a, sat_a, 100)
    hsv_b = Chameleon.HSV.new(hue_b, sat_b, 100)
    {hsv_a, hsv_b}
  end
end
