defmodule Octopus.Apps.Wood do
  use Octopus.App, category: :animation

  alias Octopus.Canvas
  alias Octopus.Events.Event.Lifecycle, as: LifecycleEvent

  @tick_ms 10
  @bounce_damping 0.9

  defmodule State do
    @moduledoc false
    defstruct [
      :display_info,
      position: 0.0,
      velocity: 0.0,
      direction: 1.0,
      global_speed: 1.0,
      blob_size: 1,
      blob_count: 1,
      blob_spacing: 1,
      mode: :endless_up,
      bounce: false,
      speed: 0.0,
      color_channel: :white,
      rgb_mode: :static,
      color: "#78c850",
      hue_cycle_speed: 30.0,
      cycle_phase: 0.0,
      trail_length: 0
    ]
  end

  def name, do: "Wood"

  def list_modes do
    [
      %{
        id: "experiment",
        name: "Experiment",
        accent_color: "#4a7c59",
        summary: "Configurable blobs on the vertical strip",
        builtin: true
      }
    ]
  end

  def mode_config("experiment"), do: %{}

  def compatible? do
    installation = Octopus.App.get_installation_info()

    installation.panel_count >= 1 and
      (installation.panel_width == 1 or installation.panel_height == 1)
  end

  def config_schema do
    [
      mode:
        {"Mode", :select,
         %{
           default: 0,
           options: [
             {"Endless up", :endless_up},
             {"Endless down", :endless_down},
             {"Up and down", :up_and_down},
             {"Full color", :fullcolor}
           ]
         }},
      blob_count:
        {"Blob count", :int,
         %{
           min: 1,
           max: 8,
           default: 1,
           visible_when: {:mode, [:endless_up, :endless_down, :up_and_down]}
         }},
      blob_spacing:
        {"Blob spacing (LEDs)", :int,
         %{
           min: 0,
           max: 12,
           default: 1,
           visible_when: {:mode, [:endless_up, :endless_down, :up_and_down]}
         }},
      bounce:
        {"Bouncy physics", :boolean,
         %{default: false, visible_when: {:mode, [:up_and_down]}}},
      blob_size: {"Blob size (LEDs)", :int, %{min: 1, max: 12, default: 1}},
      speed: {"Speed (LEDs/s)", :float, %{min: 0.0, max: 5.0, default: 0.0, step: 0.1}},
      trail_length: {"Trail length (LEDs)", :int, %{min: 0, max: 12, default: 0}},
      position: {"Position (from bottom)", :int, %{min: 0, max: 23, default: 0}},
      color_channel:
        {"Color channel", :select,
         %{
           default: 0,
           options: [{"White", :white}, {"RGB", :rgb}]
         }},
      color: {"Color", :color, %{default: "#78c850"}},
      rgb_mode:
        {"RGB mode", :select,
         %{
           default: 0,
           options: [{"Fixed color", :static}, {"Cycle hue", :cycle}]
         }},
      hue_cycle_speed: {"Hue cycle (s)", :float, %{min: 1.0, max: 120.0, default: 30.0, step: 1.0}}
    ]
  end

  def config_info(%{mode: :fullcolor}) do
    "Lights the entire strip. Pick white or RGB, optionally cycle hue."
  end

  def config_info(_config) do
    "Endless modes loop seamlessly around the strip. Up and down ping-pongs between the ends."
  end

  def get_config(%State{} = state) do
    %{
      mode: state.mode,
      blob_size: state.blob_size,
      blob_count: state.blob_count,
      blob_spacing: state.blob_spacing,
      bounce: state.bounce,
      speed: state.speed,
      color_channel: state.color_channel,
      rgb_mode: state.rgb_mode,
      color: state.color,
      hue_cycle_speed: state.hue_cycle_speed,
      trail_length: state.trail_length,
      position: trunc(state.position)
    }
  end

  def handle_config(config, %State{} = state) do
    new_state =
      state
      |> apply_config(config)
      |> Map.put(:position, Map.get(config, :position, state.position) * 1.0)
      |> reset_motion()

    render(new_state)
    maybe_schedule_tick(new_state)

    {:noreply, new_state}
  end

  def app_init(config) do
    Octopus.App.configure_display(
      layout: :gapped_panels,
      supports_rgb: true,
      supports_grayscale: true
    )

    Octopus.Params.Global.subscribe()

    display_info = Octopus.App.get_display_info()
    global_speed = Octopus.Params.Global.speed()

    state =
      %State{display_info: display_info, global_speed: global_speed}
      |> apply_config(config)
      |> Map.put(:position, Map.get(config, :position, 0) * 1.0)
      |> reset_motion()

    render(state)
    maybe_schedule_tick(state)

    {:ok, state}
  end

  def handle_event(%LifecycleEvent{type: :app_selected}, state) do
    render(state)
    maybe_schedule_tick(state)
    {:noreply, state}
  end

  def handle_event(_, state), do: {:noreply, state}

  def handle_info({:param_updated, :speed, global_speed}, %State{} = state) do
    {:noreply, %{state | global_speed: global_speed}}
  end

  def handle_info({:param_updated, _, _}, %State{} = state), do: {:noreply, state}

  def handle_info(:tick, %State{mode: :fullcolor} = state) do
    cycle_phase = maybe_advance_cycle_phase(state)

    state = %State{state | cycle_phase: cycle_phase}
    render(state)
    maybe_schedule_tick(state)

    {:noreply, state}
  end

  def handle_info(:tick, %State{speed: speed} = state) when speed <= 0.0 do
    {:noreply, state}
  end

  def handle_info(:tick, %State{} = state) do
    last = strip_length(state.display_info) - 1
    strip_len = last + 1
    dt = state.global_speed * @tick_ms / 1000.0
    step = state.speed * dt

    {position, velocity, direction} =
      case state.mode do
        :endless_up ->
          loop_step(state, step, strip_len, :endless_up)

        :endless_down ->
          loop_step(state, step, strip_len, :endless_down)

        :up_and_down ->
          if state.bounce do
            physics_step(state, dt, last)
          else
            ping_pong_step(state, step, last)
          end
      end

    cycle_phase = maybe_advance_cycle_phase(state)

    state = %State{state | position: position, velocity: velocity, direction: direction, cycle_phase: cycle_phase}
    render(state)
    schedule_tick()

    {:noreply, state}
  end

  @doc false
  def build_canvas(%State{mode: :fullcolor} = state) do
    info = state.display_info

    if state.color_channel == :white do
      Canvas.new(info.width, info.height, :grayscale) |> Canvas.fill(255)
    else
      {r, g, b} = current_rgb(state)
      Canvas.new(info.width, info.height, :rgb) |> Canvas.fill({r, g, b})
    end
  end

  def build_canvas(%State{} = state) do
    info = state.display_info
    last = strip_length(info) - 1
    strip_len = last + 1
    mode = if state.color_channel == :white, do: :grayscale, else: :rgb
    canvas = Canvas.new(info.width, info.height, mode)
    radius = blob_radius(state.blob_size)
    rgb = if mode == :rgb, do: current_rgb(state), else: {0, 0, 0}
    wrap? = endless?(state)
    base = if wrap?, do: state.position, else: wrap_coord(state.position, strip_len)

    blob_centers_from_bottom(base, state, last)
    |> Enum.reduce(canvas, fn center_bottom, canvas ->
      canvas
      |> draw_trail(info, center_bottom, state, radius, last, strip_len, mode, rgb, wrap?)
      |> draw_blob(info, center_bottom, state.blob_size, last, strip_len, mode, rgb, 1.0, wrap?)
    end)
  end

  @doc false
  def loop_step(%State{position: position} = state, step, strip_len, movement \\ nil) do
    movement = movement || state.mode
    delta = if movement == :endless_down, do: -step, else: step
    direction = if movement == :endless_down, do: -1.0, else: 1.0
    {wrap_coord(position + delta, strip_len), state.velocity, direction}
  end

  @doc false
  def ping_pong_step(%State{position: position, direction: direction}, step, last) do
    bounce(position + direction * step, direction, last)
  end

  def bounce(_position, direction, last) when last == 0, do: {0.0, 0.0, direction}

  def bounce(position, direction, last) do
    cond do
      position > last ->
        overshoot = position - last
        {last - overshoot, 0.0, -direction}

      position < 0 ->
        {-position, 0.0, -direction}

      true ->
        {position, 0.0, direction}
    end
  end

  @doc false
  def physics_step(%State{} = state, dt, last) do
    target_v = ping_pong_speed(state) * state.global_speed
    velocity = state.velocity + (target_v - state.velocity) * min(1.0, dt * 10.0)
    position = state.position + velocity * dt

    {position, velocity} =
      cond do
        position < 0 ->
          {position * -@bounce_damping, abs(velocity) * @bounce_damping}

        position > last ->
          overshoot = position - last
          {last - overshoot * @bounce_damping, -abs(velocity) * @bounce_damping}

        true ->
          {position, velocity}
      end

    direction = if velocity >= 0, do: 1.0, else: -1.0
    {position, velocity, direction}
  end

  @doc false
  def wrap_coord(position, strip_len) do
    wrapped = :math.fmod(position, strip_len * 1.0)
    if wrapped < 0, do: wrapped + strip_len, else: wrapped
  end

  defp apply_config(%State{} = state, config) do
    mode = Map.get(config, :mode, Map.get(config, :movement, state.mode))

    %{
      state
      | mode: mode,
        blob_size: Map.get(config, :blob_size, state.blob_size),
        blob_count: Map.get(config, :blob_count, state.blob_count),
        blob_spacing: Map.get(config, :blob_spacing, state.blob_spacing),
        bounce: Map.get(config, :bounce, state.bounce),
        speed: Map.get(config, :speed, state.speed),
        color_channel: Map.get(config, :color_channel, state.color_channel),
        rgb_mode: Map.get(config, :rgb_mode, state.rgb_mode),
        color: Map.get(config, :color, state.color),
        hue_cycle_speed: Map.get(config, :hue_cycle_speed, state.hue_cycle_speed),
        trail_length: Map.get(config, :trail_length, state.trail_length)
    }
  end

  defp reset_motion(%State{mode: :up_and_down, bounce: true} = state) do
    %{state | velocity: ping_pong_speed(state), direction: state.direction || 1.0}
  end

  defp reset_motion(%State{mode: :up_and_down} = state) do
    %{state | velocity: 0.0, direction: state.direction || 1.0}
  end

  defp reset_motion(%State{mode: :endless_down} = state) do
    %{state | velocity: 0.0, direction: -1.0}
  end

  defp reset_motion(%State{} = state) do
    %{state | velocity: 0.0, direction: 1.0}
  end

  defp ping_pong_speed(%State{direction: dir, speed: speed}) when dir < 0, do: -speed
  defp ping_pong_speed(%State{speed: speed}), do: speed

  defp endless?(%State{mode: mode}), do: mode in [:endless_up, :endless_down]

  defp render(%State{} = state) do
    canvas = build_canvas(state)

    case state.color_channel do
      :white -> Octopus.App.update_display(canvas, :grayscale)
      :rgb -> Octopus.App.update_display(canvas, :rgb)
    end
  end

  defp maybe_schedule_tick(%State{mode: :fullcolor, color_channel: :rgb, rgb_mode: :cycle}) do
    schedule_tick()
  end

  defp maybe_schedule_tick(%State{speed: speed}) when speed > 0.0, do: schedule_tick()
  defp maybe_schedule_tick(_state), do: :ok

  defp schedule_tick, do: :timer.send_after(@tick_ms, :tick)

  defp maybe_advance_cycle_phase(%State{color_channel: :rgb, rgb_mode: :cycle} = state) do
    advance_cycle_phase(state.cycle_phase, state.hue_cycle_speed, @tick_ms, state.global_speed)
  end

  defp maybe_advance_cycle_phase(%State{cycle_phase: phase}), do: phase

  defp advance_cycle_phase(phase, cycle_seconds, tick_ms, global_speed) do
    phase + tick_ms / (cycle_seconds * 1000.0) * global_speed
  end

  defp blob_centers_from_bottom(base, %State{} = state, _last) do
    step = state.blob_size + state.blob_spacing
    count = effective_blob_count(state)

    for i <- 0..(count - 1) do
      base + i * step
    end
  end

  defp effective_blob_count(%State{mode: :fullcolor}), do: 1
  defp effective_blob_count(%State{blob_count: count}), do: count

  defp draw_trail(canvas, info, center_bottom, %State{} = state, _radius, last, strip_len, mode, rgb, wrap?) do
    if state.trail_length > 0 and state.speed > 0 and state.direction != 0 do
      for t <- 1..state.trail_length, reduce: canvas do
        canvas ->
          raw_center = center_bottom - state.direction * t
          trail_center = if wrap?, do: wrap_coord(raw_center, strip_len), else: raw_center
          intensity = trail_falloff(t, state.trail_length)

          if intensity > 0 and (wrap? or (trail_center >= 0 and trail_center <= last)) do
            draw_blob(canvas, info, trail_center, state.blob_size, last, strip_len, mode, rgb, intensity, wrap?)
          else
            canvas
          end
      end
    else
      canvas
    end
  end

  defp draw_blob(canvas, info, center_bottom, blob_size, last, strip_len, mode, rgb, scale, wrap?) do
    for bottom_coord <- blob_bottom_coords(center_bottom, blob_size, last, wrap?, strip_len), reduce: canvas do
      canvas ->
        intensity =
          if blob_size == 1 do
            falloff(abs(bottom_coord - center_bottom), 0, 1) * scale
          else
            scale
          end

        if intensity > 0 do
          strip_coord = bottom_to_strip_coord(last, bottom_coord)
          {local_x, local_y} = strip_coords(info, strip_coord)

          case info.panel_to_global_coords.(0, local_x, local_y) do
            :invalid_panel ->
              canvas

            {x, y} ->
              put_lit_pixel(canvas, {x, y}, intensity, mode, rgb)
          end
        else
          canvas
        end
    end
  end

  defp blob_bottom_coords(center_bottom, blob_size, _last, true, strip_len) do
    center = round(center_bottom)
    low = center - div(blob_size - 1, 2)

    for i <- 0..(blob_size - 1) do
      wrap_coord(low + i * 1.0, strip_len)
    end
  end

  defp blob_bottom_coords(center_bottom, blob_size, last, false, _strip_len) do
    center = round(center_bottom)
    low = max(center - div(blob_size - 1, 2), 0)
    high = min(low + blob_size - 1, last)
    for bottom_coord <- low..high, do: bottom_coord * 1.0
  end

  defp put_lit_pixel(canvas, coord, intensity, :grayscale, _rgb) do
    value = trunc(255 * intensity)
    existing = Canvas.get_pixel(canvas, coord)
    Canvas.put_pixel(canvas, coord, max(existing, value))
  end

  defp put_lit_pixel(canvas, coord, intensity, :rgb, {r, g, b}) do
    {cr, cg, cb} = {trunc(r * intensity), trunc(g * intensity), trunc(b * intensity)}
    {er, eg, eb} = Canvas.get_pixel(canvas, coord)
    Canvas.put_pixel(canvas, coord, {max(er, cr), max(eg, cg), max(eb, cb)})
  end

  defp current_rgb(%State{color_channel: :rgb} = state) do
    {r, g, b} = parse_hex_color(state.color)

    if state.rgb_mode == :cycle do
      hue_shift = :math.fmod(state.cycle_phase, 1.0) * 360.0
      rotate_rgb({r, g, b}, hue_shift)
    else
      {r, g, b}
    end
  end

  defp parse_hex_color("#" <> hex) when byte_size(hex) == 6 do
    {r, ""} = Integer.parse(String.slice(hex, 0, 2), 16)
    {g, ""} = Integer.parse(String.slice(hex, 2, 2), 16)
    {b, ""} = Integer.parse(String.slice(hex, 3, 2), 16)
    {r, g, b}
  end

  defp parse_hex_color(_), do: {120, 200, 80}

  defp rotate_rgb({r, g, b}, degrees) do
    %Chameleon.RGB{r: r, g: g, b: b} =
      Chameleon.RGB.new(r, g, b)
      |> Chameleon.convert(Chameleon.HSL)
      |> then(fn %Chameleon.HSL{h: h, s: s, l: l} ->
        Chameleon.HSL.new(:math.fmod(h + degrees, 360.0), s, l)
      end)
      |> Chameleon.convert(Chameleon.RGB)

    {r, g, b}
  end

  defp trail_falloff(_distance, length) when length <= 0, do: 0.0

  defp trail_falloff(distance, length) do
    t = 1 - (distance - 1) / length
    t = max(0.0, min(1.0, t))
    t * t
  end

  defp bottom_to_strip_coord(last, bottom_coord), do: last - trunc(bottom_coord)

  defp strip_length(%{panel_width: panel_width, panel_height: panel_height}) do
    max(panel_width, panel_height)
  end

  defp strip_coords(%{panel_width: panel_width, panel_height: panel_height}, coord) do
    if panel_width >= panel_height do
      {coord, 0}
    else
      {0, coord}
    end
  end

  defp blob_radius(size), do: (size - 1) / 2

  defp falloff(distance, _radius, 1) do
    if distance <= 0.5, do: 1.0, else: 0.0
  end

  defp falloff(distance, radius, _blob_size) do
    if distance <= radius, do: 1.0, else: 0.0
  end
end
