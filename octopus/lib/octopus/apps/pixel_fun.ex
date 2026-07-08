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

  @default_cycle_interval_seconds 300.0

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
      # Ordered playlist of scene ids the wall rotates through (any length).
      :cycle_preset_ids,
      # Interval between scene changes, in seconds.
      :cycle_interval_seconds,
      # Current position within the queue.
      :cycle_index,
      :cycle_timer_ref,
      # Transport state.
      :playing,
      :paused_remaining_ms,
      :next_change_at_ms,
      # Id of the scene currently rendered on the wall.
      :live_scene_id,
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
      cycle_interval_seconds: {"", :internal, %{default: @default_cycle_interval_seconds}}
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
      cycle_preset_ids: state.cycle_preset_ids,
      cycle_interval_seconds: state.cycle_interval_seconds,
      cycle_index: state.cycle_index,
      playing: state.playing,
      next_change_at_ms: state.next_change_at_ms,
      paused_remaining_ms: state.paused_remaining_ms,
      live_scene_id: live_scene_id(state, scene),
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

    cycle_interval_seconds =
      Map.get(config, :cycle_interval_seconds, @default_cycle_interval_seconds)

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
      cycle_interval_seconds: cycle_interval_seconds,
      cycle_index: 0,
      cycle_timer_ref: nil,
      playing: true,
      paused_remaining_ms: nil,
      next_change_at_ms: nil,
      live_scene_id: nil,
      offset: {0, 0},
      move: {0, 0},
      audio_input: %{low: 0.0, mid: 0.0, high: 0.0},
      seconds: seconds,
      buttons: %{},
      panel_interaction_factors: panel_interaction_factors,
      panel_proximities: Map.new(0..(Installation.num_panels() - 1), fn i -> {i, 0.0} end),
      speed: Octopus.Params.Global.speed()
    }

    state = apply_queue_head_on_init(state)

    {:ok, state}
  end

  # `handle_config` handles scene-editor changes (formula + sliders). Queue,
  # interval and transport are driven through the dedicated casts below so the
  # running countdown is never disturbed by an editor keystroke.
  def handle_config(config, %State{} = state) do
    new_state = apply_scene_fields(state, config)

    new_state =
      case Map.fetch(config, :cycle_preset_ids) do
        {:ok, ids} -> apply_queue(new_state, normalize_cycle_ids(ids))
        :error -> new_state
      end

    new_state =
      case Map.fetch(config, :cycle_interval_seconds) do
        # Interval change only swaps the stored value — the scheduled change
        # keeps its deadline; the new value is used the next time we schedule.
        {:ok, seconds} -> %State{new_state | cycle_interval_seconds: normalize_interval(seconds)}
        :error -> new_state
      end

    {:noreply, new_state}
  end

  # -- Transport / queue API -------------------------------------------------

  @doc "Toggles play/pause on the running app."
  def toggle_play(app_id), do: cast(app_id, :toggle_play)

  @doc "Advances to the next queued scene and restarts the countdown."
  def next_scene(app_id), do: cast(app_id, :next_scene)

  @doc "Returns to the previous queued scene and restarts the countdown."
  def prev_scene(app_id), do: cast(app_id, :prev_scene)

  @doc "Plays the given scene immediately, jumping the queue position if queued."
  def play_now(app_id, scene_id), do: cast(app_id, {:play_now, scene_id})

  @doc "Replaces the queue with the given ordered list of scene ids."
  def set_queue(app_id, ids), do: cast(app_id, {:set_queue, ids})

  @doc "Sets the rotation interval in seconds (does not reset the countdown)."
  def set_interval(app_id, seconds), do: cast(app_id, {:set_interval, seconds})

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

  def handle_cast(:toggle_play, %State{playing: true} = state) do
    {:noreply, state |> pause() |> broadcast()}
  end

  def handle_cast(:toggle_play, %State{playing: false} = state) do
    {:noreply, state |> resume() |> broadcast()}
  end

  def handle_cast(:next_scene, %State{} = state) do
    {:noreply, state |> step_scene(+1) |> broadcast()}
  end

  def handle_cast(:prev_scene, %State{} = state) do
    {:noreply, state |> step_scene(-1) |> broadcast()}
  end

  def handle_cast({:play_now, scene_id}, %State{} = state) do
    {:noreply, state |> do_play_now(to_string(scene_id)) |> broadcast()}
  end

  def handle_cast({:set_queue, ids}, %State{} = state) do
    {:noreply, state |> apply_queue(normalize_cycle_ids(ids)) |> broadcast()}
  end

  def handle_cast({:set_interval, seconds}, %State{} = state) do
    {:noreply, %State{state | cycle_interval_seconds: normalize_interval(seconds)} |> broadcast()}
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

  defp normalize_interval(seconds) when is_number(seconds), do: seconds * 1.0 |> max(1.0)
  defp normalize_interval(_), do: @default_cycle_interval_seconds

  defp now_ms, do: System.os_time(:millisecond)

  defp interval_ms(%State{cycle_interval_seconds: seconds}) do
    seconds |> normalize_interval() |> Kernel.*(1000) |> trunc() |> max(1)
  end

  # Applies the first queued scene (if any) and starts the countdown on boot.
  defp apply_queue_head_on_init(%State{cycle_preset_ids: []} = state) do
    schedule_change(state)
  end

  defp apply_queue_head_on_init(%State{cycle_preset_ids: [id | _]} = state) do
    state = apply_scene_by_id(state, id)
    %State{state | cycle_index: 0, live_scene_id: id} |> schedule_change()
  end

  # Replaces the queue, clamps the current index, and (re)schedules the timer
  # only when membership/order actually changed. Applying a new queue also
  # loads its head scene when the queue was previously empty.
  defp apply_queue(%State{cycle_preset_ids: same} = state, same), do: state

  defp apply_queue(%State{} = state, ids) do
    index = clamp_index(state.cycle_index, ids)

    %State{state | cycle_preset_ids: ids, cycle_index: index}
    |> schedule_change()
  end

  defp clamp_index(_index, []), do: 0
  defp clamp_index(index, ids), do: index |> max(0) |> min(length(ids) - 1)

  # Schedules the next scene change. No timer when holding (0/1 queued) or
  # paused. Preserves an already-running deadline unless we're (re)starting.
  defp schedule_change(%State{playing: false} = state), do: cancel_cycle_timer(state)

  defp schedule_change(%State{cycle_preset_ids: ids} = state) when length(ids) < 2 do
    %State{cancel_cycle_timer(state) | next_change_at_ms: nil}
  end

  defp schedule_change(%State{next_change_at_ms: deadline} = state)
       when is_integer(deadline) and deadline > 0 do
    # Already counting down — keep the existing deadline (used on interval and
    # membership tweaks that must not reset the running countdown).
    remaining = max(deadline - now_ms(), 1)
    arm_timer(state, remaining, deadline)
  end

  defp schedule_change(%State{} = state), do: restart_countdown(state)

  # Cancels any timer and arms a fresh full-interval countdown.
  defp restart_countdown(%State{cycle_preset_ids: ids} = state) when length(ids) < 2 do
    %State{cancel_cycle_timer(state) | next_change_at_ms: nil}
  end

  defp restart_countdown(%State{playing: false} = state) do
    %State{cancel_cycle_timer(state) | next_change_at_ms: nil}
  end

  defp restart_countdown(%State{} = state) do
    ms = interval_ms(state)
    arm_timer(state, ms, now_ms() + ms)
  end

  defp arm_timer(%State{} = state, remaining_ms, deadline_ms) do
    state = cancel_cycle_timer(state)
    ref = Process.send_after(self(), :cycle_presets, remaining_ms)
    %State{state | cycle_timer_ref: ref, next_change_at_ms: deadline_ms, paused_remaining_ms: nil}
  end

  defp cancel_cycle_timer(%State{cycle_timer_ref: nil} = state), do: state

  defp cancel_cycle_timer(%State{cycle_timer_ref: ref} = state) do
    Process.cancel_timer(ref)
    %State{state | cycle_timer_ref: nil}
  end

  defp pause(%State{} = state) do
    remaining =
      case state.next_change_at_ms do
        deadline when is_integer(deadline) -> max(deadline - now_ms(), 0)
        _ -> nil
      end

    %State{cancel_cycle_timer(state) | playing: false, paused_remaining_ms: remaining, next_change_at_ms: nil}
  end

  defp resume(%State{cycle_preset_ids: ids} = state) when length(ids) < 2 do
    %State{state | playing: true, paused_remaining_ms: nil, next_change_at_ms: nil}
  end

  defp resume(%State{paused_remaining_ms: remaining} = state) when is_integer(remaining) do
    remaining = max(remaining, 1)
    arm_timer(%State{state | playing: true}, remaining, now_ms() + remaining)
  end

  defp resume(%State{} = state) do
    restart_countdown(%State{state | playing: true})
  end

  # Advance/retreat by one queue position, load the scene, restart countdown.
  defp step_scene(%State{cycle_preset_ids: ids} = state, _dir) when length(ids) < 2, do: state

  defp step_scene(%State{cycle_preset_ids: ids, cycle_index: index} = state, dir) do
    next_index = Integer.mod(index + dir, length(ids))
    id = Enum.at(ids, next_index)
    state = apply_scene_by_id(state, id)

    %State{state | cycle_index: next_index, live_scene_id: id} |> restart_countdown()
  end

  defp do_play_now(%State{cycle_preset_ids: ids} = state, scene_id) do
    state = apply_scene_by_id(state, scene_id)
    state = %State{state | live_scene_id: scene_id}

    case Enum.find_index(ids, &(&1 == scene_id)) do
      nil -> state
      index -> %State{state | cycle_index: index} |> restart_countdown()
    end
  end

  defp apply_scene_by_id(%State{} = state, scene_id) do
    case ScenePresets.get(scene_id) do
      nil -> state
      preset -> apply_scene_fields(state, ScenePresets.to_config(preset))
    end
  end

  defp broadcast(%State{} = state) do
    broadcast_config(state)
    state
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
  defp live_scene_id(_state, scene), do: ScenePresets.id_for_config(scene)

  defp running_preset_id(%State{live_scene_id: id}, _scene) when is_binary(id), do: id
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

    applied = apply_scene_by_id(state, preset_id)

    new_state =
      %State{applied | cycle_index: next_index, live_scene_id: preset_id}
      |> restart_countdown()

    broadcast_config(new_state)
    {:noreply, new_state}
  end

  def handle_info(:cycle_presets, %State{} = state) do
    {:noreply, restart_countdown(state)}
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
