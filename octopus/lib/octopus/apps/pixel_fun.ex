defmodule Octopus.Apps.PixelFun do
  use Octopus.App, category: :interactive
  use Octopus.Params, prefix: :pixelfun

  alias Octopus.Canvas
  alias Octopus.Events.Event.Audio, as: AudioEvent
  alias Octopus.Events.Event.Input, as: InputEvent
  alias Octopus.Events.Event.Proximity, as: ProximityEvent
  alias Octopus.AppSupervisor
  alias Octopus.Apps.PixelFun.Program
  alias Octopus.Apps.PixelFun.ScenePresets
  alias Octopus.Installation

  @default_cycle_interval_minutes 5.0

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
      :cycle_preset_ids,
      :cycle_interval_minutes,
      :cycle_index,
      :cycle_timer_ref,
      :offset,
      :move,
      :audio_input,
      :seconds,
      :buttons,
      :panel_interaction_factors,
      :panel_proximities,
      :speed
    ]
  end

  def name(), do: "Pixel Fun"

  def compatible?() do
    installation_info = Octopus.App.get_installation_info()
    installation_info.panel_width == 8 and installation_info.panel_height == 8
  end

  def config_schema() do
    %{
      program: {"Formula", :string, %{default: "sin(10*t-hypot(x,y))"}},
      color_interval:
        {"Palette crossfade (s)", :float, %{default: 5, min: 1, max: 20, step: 0.5}},
      translate_scale: {"Drift strength", :float, %{default: 0.0, min: 0, max: 20, step: 0.1}},
      rotate_scale: {"Rotation speed", :float, %{default: 0.0, min: 0, max: 4, step: 0.01}},
      zoom_scale: {"Zoom pulse strength", :float, %{default: 1.0, min: 0, max: 10, step: 0.1}},
      cycle_preset_ids: {"", :internal, %{default: []}},
      cycle_interval_minutes: {"", :internal, %{default: @default_cycle_interval_minutes}}
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

    Scene presets — click a tile to load formula and sliders. Enable loop on two or more tiles to auto-rotate every N minutes.
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
      cycle_preset_ids: state.cycle_preset_ids,
      cycle_interval_minutes: state.cycle_interval_minutes,
      cycle_index: state.cycle_index,
      active_preset_id: running_preset_id(state, scene)
    })
  end

  def app_init(config) do
    # Configure display using new unified API - adjacent layout (was Canvas.to_frame())
    Octopus.App.configure_display(layout: :adjacent_panels)
    Octopus.App.subscribe_to_button_events()
    Octopus.Params.Global.subscribe()

    {:ok, program} = config.program |> Program.parse()

    :timer.send_interval(@frame_time_ms, :tick)
    Process.send_after(self(), :update_colors, color_interval_ms(config.color_interval))

    {seconds, micros} = NaiveDateTime.utc_now() |> NaiveDateTime.to_gregorian_seconds()
    seconds = seconds + micros / 1_000_000

    panel_interaction_factors =
      0..(Installation.num_panels() - 1) |> Enum.map(fn i -> {i, 0.0} end) |> Map.new()

    cycle_preset_ids = normalize_cycle_ids(Map.get(config, :cycle_preset_ids, []))

    cycle_interval_minutes =
      Map.get(config, :cycle_interval_minutes, @default_cycle_interval_minutes)

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
      cycle_preset_ids: cycle_preset_ids,
      cycle_interval_minutes: cycle_interval_minutes,
      cycle_index: 0,
      cycle_timer_ref: nil,
      offset: {0, 0},
      move: {0, 0},
      audio_input: %{low: 0.0, mid: 0.0, high: 0.0},
      seconds: seconds,
      buttons: %{},
      panel_interaction_factors: panel_interaction_factors,
      panel_proximities: Map.new(0..(Installation.num_panels() - 1), fn i -> {i, 0.0} end),
      speed: Octopus.Params.Global.speed()
    }

    state =
      state
      |> sync_cycle_timer()
      |> maybe_apply_cycle_preset_on_init()

    {:ok, state}
  end

  def handle_config(config, %State{} = state) do
    cycle_preset_ids = cycle_preset_ids_from_config(config, state)
    cycle_interval_minutes = cycle_interval_from_config(config, state)

    new_state =
      case apply_scene_fields(state, config) do
        %State{} = updated ->
          %State{
            updated
            | cycle_preset_ids: cycle_preset_ids,
              cycle_interval_minutes: cycle_interval_minutes
          }
      end
      |> sync_cycle_timer()

    {new_state, _rebroadcast?} = maybe_apply_cycle_preset(state, new_state)

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

  defp apply_scene_fields(%State{} = state, config) do
    program_source = Map.get(config, :program, state.source)

    program =
      case Program.parse(program_source) do
        {:ok, program} -> program
        _ -> state.program
      end

    color_interval = Map.get(config, :color_interval, state.color_interval)

    %State{
      state
      | program: program,
        source: program_source,
        translate_scale: Map.get(config, :translate_scale, state.translate_scale),
        rotate_scale: Map.get(config, :rotate_scale, state.rotate_scale),
        zoom_scale: Map.get(config, :zoom_scale, state.zoom_scale),
        color_interval: color_interval
    }
  end

  defp normalize_cycle_ids(nil), do: []

  defp normalize_cycle_ids(ids) when is_list(ids) do
    ids
    |> Enum.map(&to_string/1)
    |> Enum.uniq()
  end

  defp normalize_cycle_ids(_), do: []

  defp cycle_preset_ids_from_config(config, %State{} = state) do
    case Map.fetch(config, :cycle_preset_ids) do
      {:ok, ids} -> normalize_cycle_ids(ids)
      :error -> normalize_cycle_ids(state.cycle_preset_ids)
    end
  end

  defp cycle_interval_from_config(config, %State{} = state) do
    case Map.fetch(config, :cycle_interval_minutes) do
      {:ok, minutes} -> minutes
      :error -> state.cycle_interval_minutes
    end
  end

  defp sync_cycle_timer(%State{} = state) do
    state = cancel_cycle_timer(state)

    if length(state.cycle_preset_ids) >= 2 do
      ref = Process.send_after(self(), :cycle_presets, cycle_interval_ms(state.cycle_interval_minutes))
      %State{state | cycle_timer_ref: ref}
    else
      %State{state | cycle_timer_ref: nil, cycle_index: 0}
    end
  end

  defp cancel_cycle_timer(%State{cycle_timer_ref: nil} = state), do: state

  defp cancel_cycle_timer(%State{cycle_timer_ref: ref} = state) do
    Process.cancel_timer(ref)
    %State{state | cycle_timer_ref: nil}
  end

  defp cycle_interval_ms(minutes) when is_number(minutes) do
    minutes
    |> max(1.0)
    |> Kernel.*(60_000)
    |> trunc()
    |> max(1)
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

  defp maybe_apply_cycle_preset_on_init(%State{cycle_preset_ids: []} = state), do: state

  defp maybe_apply_cycle_preset_on_init(%State{} = state) do
    {applied, _} = maybe_apply_cycle_preset(%State{state | cycle_preset_ids: []}, state)
    applied
  end

  defp maybe_apply_cycle_preset(%State{} = old_state, %State{} = new_state) do
    old_ids = old_state.cycle_preset_ids
    new_ids = new_state.cycle_preset_ids

    if new_ids == old_ids do
      {new_state, false}
    else
      case new_ids do
        [id] ->
          {apply_cycle_preset(new_state, id), true}

        ids when length(ids) >= 2 ->
          id = Enum.at(ids, 0)
          {apply_cycle_preset(%State{new_state | cycle_index: 0}, id), true}

        _ ->
          {new_state, false}
      end
    end
  end

  defp apply_cycle_preset(%State{} = state, preset_id) do
    case ScenePresets.get(preset_id) do
      nil -> state
      preset -> apply_scene_fields(state, ScenePresets.to_config(preset))
    end
  end

  defp running_preset_id(%State{cycle_preset_ids: [id]}, _scene), do: id

  defp running_preset_id(%State{cycle_preset_ids: ids, cycle_index: index}, _scene)
       when length(ids) >= 2 do
    Enum.at(ids, index)
  end

  defp running_preset_id(_state, scene), do: ScenePresets.id_for_config(scene)

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

  def handle_info(:cycle_presets, %State{cycle_preset_ids: ids} = state) when length(ids) >= 2 do
    next_index = rem(state.cycle_index + 1, length(ids))
    preset_id = Enum.at(ids, next_index)

    new_state =
      case ScenePresets.get(preset_id) do
        nil ->
          %State{state | cycle_index: next_index}

        preset ->
          updated = apply_scene_fields(state, ScenePresets.to_config(preset))
          %State{updated | cycle_index: next_index}
      end
      |> sync_cycle_timer()

    broadcast_config(new_state)
    {:noreply, new_state}
  end

  def handle_info(:cycle_presets, %State{} = state) do
    {:noreply, sync_cycle_timer(state)}
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

  defp render(%State{program: program} = state) do
    {offset_x, offset_y} = translate_offset(state)
    zoom = zoom_factor(state)
    rotation = state.seconds * state.rotate_scale

    center_x = Installation.width() / 2 - 0.5
    center_y = Installation.height() / 2 - 0.5

    Installation.virtual_pixel_positions_per_panel()
    |> Enum.with_index()
    |> Enum.map(fn {panel, index} ->
      proximity = Map.get(state.panel_proximities, index, 0.0)
      hue_shift = proximity * 180 * 5
      interaction_factor = Map.get(state.panel_interaction_factors, index, 0.0)

      {color_a, color_b} = state.colors

      colors = {
        %Chameleon.HSV{(%Chameleon.HSV{} = color_a) | h: rem(trunc(color_a.h + hue_shift), 360)},
        %Chameleon.HSV{(%Chameleon.HSV{} = color_b) | h: rem(trunc(color_b.h + hue_shift), 360)}
      }

      for {{x, y}, i} <- Enum.with_index(panel), into: Canvas.new(8, 8) do
        local_x = rem(i, 8)
        local_y = div(i, 8)

        x_translated = x - offset_x - center_x
        y_translated = y - offset_y - center_y

        x_rotated = x_translated * :math.cos(rotation) - y_translated * :math.sin(rotation)
        y_rotated = x_translated * :math.sin(rotation) + y_translated * :math.cos(rotation)

        x_scaled = x_rotated * zoom
        y_scaled = y_rotated * zoom

        {{local_x, local_y},
         pixels(
           program,
           x_scaled,
           y_scaled,
           i,
           state.seconds + interaction_factor * 5,
           state.audio_input.low,
           state.audio_input.mid,
           state.audio_input.high,
           colors,
           &interpolate_colors_with_black/3
         )}
      end
    end)
    |> Enum.reduce(&Canvas.join(&2, &1))
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
