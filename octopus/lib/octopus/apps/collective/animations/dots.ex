defmodule Octopus.Apps.Collective.Animations.Dots do
  @moduledoc """
  Crowd Dots — one pixel per person on the ring strip.

  * X — angular position (frame-panel mapping via `PanelMapping`)
  * Y — radius: ring / near panels → top; centre → bottom
  * Panel activity — warm-white (W) channel glow from `Radar.panel_factors/0`
  * Velocity — walking speed drives a soft cosine blink on each dot
  * Still 3 s → soft expanding ring pulse (~3–4 panels), then fade
  """

  @behaviour Octopus.Apps.Collective.Animation

  alias Octopus.Canvas
  alias Octopus.Radar
  alias Octopus.Radar.PanelMapping

  @panel_width 8
  @two_pi 2.0 * :math.pi()

  @still_s 3.0
  @move_speed 0.15
  @move_dist 0.2

  @pulse_ttl 1.5
  @pulse_max_radius 30.0
  @pulse_ring_width 2.2
  @pulse_strength 0.5
  @y_scale 2.5

  @activity_floor 0.08
  @activity_gain 0.90
  @activity_cap 0.55

  @blink_speed_min 0.12
  @blink_speed_max 1.0
  @blink_hz_min 0.8
  @blink_hz_max 3.5
  @blink_dim_min 0.35
  @blink_dim_max 0.65

  @impl true
  def name, do: "Crowd Dots"

  @doc """
  Builds the W-channel canvas: per-panel grayscale from panel activity.
  """
  @spec activity_canvas(map(), float()) :: Canvas.t()
  def activity_canvas(display_info, bleed \\ 0.2) do
    width = display_info.width
    height = display_info.height
    num_panels = max(div(width, @panel_width), 1)
    bleed = bleed |> clamp01()

    Canvas.new(width, height, :grayscale)
    |> draw_activity_white(num_panels, height, bleed)
  end

  @impl true
  def init(_display_info) do
    %{
      positions: %{},
      still_for: %{},
      still_armed: %{},
      last_world: %{},
      blink_phase: %{},
      pulses: []
    }
  end

  @impl true
  def render(canvas, people, ctx, state) do
    dt = ctx.dt
    width = canvas.width
    height = canvas.height
    num_panels = max(div(width, @panel_width), 1)

    smooth = Map.get(ctx, :dots_smoothing, 0.35) |> clamp01()
    tau = lerp(0.04, 0.22, smooth)
    alpha = 1.0 - :math.exp(-dt / tau)

    active_ids = MapSet.new(people, & &1.id)

    {positions, still_for, still_armed, last_world, blink_phase, new_pulses} =
      Enum.reduce(people, {state.positions, state.still_for, state.still_armed, state.last_world, state.blink_phase, []}, fn person,
                                                                                                                              {pos_acc,
                                                                                                                               still_acc,
                                                                                                                               armed_acc,
                                                                                                                               world_acc,
                                                                                                                               blink_acc,
                                                                                                                               pulse_acc} ->
        target = PanelMapping.track_to_canvas_xy(person, num_panels, height, @panel_width)
        {sx, sy} = Map.get(pos_acc, person.id, target)
        sx = sx + (elem(target, 0) - sx) * alpha
        sy = sy + (elem(target, 1) - sy) * alpha
        pos_acc = Map.put(pos_acc, person.id, {sx, sy})

        last = Map.get(world_acc, person.id)
        world_acc = Map.put(world_acc, person.id, {person.x, person.y})

        {still_t, armed} =
          if moving?(person, last) do
            {0.0, true}
          else
            t = Map.get(still_acc, person.id, 0.0) + dt
            {t, Map.get(armed_acc, person.id, true)}
          end

        still_acc = Map.put(still_acc, person.id, still_t)

        {armed, pulse_acc} =
          if still_t >= @still_s and armed do
            pulse = %{
              cx: sx,
              cy: sy,
              age: 0.0,
              color: pulse_color(person.id)
            }

            {false, [pulse | pulse_acc]}
          else
            {armed, pulse_acc}
          end

        armed_acc = Map.put(armed_acc, person.id, armed)

        phase = Map.get(blink_acc, person.id, 0.0)
        blink_acc = Map.put(blink_acc, person.id, advance_blink_phase(phase, person, dt))

        {pos_acc, still_acc, armed_acc, world_acc, blink_acc, pulse_acc}
      end)

    positions = Map.take(positions, MapSet.to_list(active_ids))
    still_for = Map.take(still_for, MapSet.to_list(active_ids))
    still_armed = Map.take(still_armed, MapSet.to_list(active_ids))
    last_world = Map.take(last_world, MapSet.to_list(active_ids))
    blink_phase = Map.take(blink_phase, MapSet.to_list(active_ids))

    pulses =
      state.pulses
      |> Kernel.++(new_pulses)
      |> step_pulses(dt)

    canvas =
      canvas
      |> draw_pulses(pulses, width, height)
      |> draw_people(people, positions, blink_phase, width, height)

    {canvas,
     %{
       state
       | positions: positions,
         still_for: still_for,
         still_armed: still_armed,
         last_world: last_world,
         blink_phase: blink_phase,
         pulses: pulses
     }}
  end

  defp moving?(person, nil), do: PanelMapping.track_speed(person) > @move_speed

  defp moving?(person, {lx, ly}) do
    PanelMapping.track_speed(person) > @move_speed or
      dist_sq(person.x - lx, person.y - ly) > @move_dist * @move_dist
  end

  defp dist_sq(dx, dy), do: dx * dx + dy * dy

  defp draw_activity_white(canvas, num_panels, height, bleed) do
    levels = frame_activity_levels(num_panels, bleed)

    Enum.reduce(0..(num_panels - 1), canvas, fn p, c ->
      gray = activity_gray(Map.get(levels, p, 0.0))
      x0 = p * @panel_width
      x1 = x0 + @panel_width - 1
      Canvas.fill_rect(c, {x0, 0}, {x1, height - 1}, gray)
    end)
  end

  defp activity_gray(level) when level <= 0.0, do: 0

  defp activity_gray(level) do
    brightness =
      @activity_floor + (@activity_cap - @activity_floor) * clamp01(level * @activity_gain)

    trunc(brightness * 255)
  end

  defp frame_activity_levels(num_panels, bleed) do
    factors = Radar.panel_factors()
    north = Radar.north_panel()

    for frame_panel <- 0..(num_panels - 1), into: %{} do
      install = PanelMapping.installation_panel_of_frame(frame_panel, num_panels, north)
      base = Map.get(factors, install, 0.0)

      left = Map.get(factors, wrap_install_panel(install - 1, num_panels), 0.0)
      right = Map.get(factors, wrap_install_panel(install + 1, num_panels), 0.0)

      level = clamp01(base + bleed * (left + right) / 2.0)
      {frame_panel, level}
    end
  end

  defp wrap_install_panel(panel, num_panels) do
    rem(rem(panel - 1, num_panels) + num_panels, num_panels) + 1
  end

  defp advance_blink_phase(phase, person, dt) do
    speed = PanelMapping.track_speed(person)

    if speed > @blink_speed_min do
      t = normalize_speed(speed)
      freq = lerp(@blink_hz_min, @blink_hz_max, t)
      phase + @two_pi * freq * dt
    else
      0.0
    end
  end

  defp blink_glow(phase, person) do
    speed = PanelMapping.track_speed(person)

    if speed > @blink_speed_min do
      t = normalize_speed(speed)
      wave = (1.0 - :math.cos(phase)) * 0.5
      depth = lerp(@blink_dim_min, @blink_dim_max, t)
      1.0 - depth * (1.0 - wave)
    else
      1.0
    end
  end

  defp normalize_speed(speed) do
    (speed - @blink_speed_min) / (@blink_speed_max - @blink_speed_min) |> clamp01()
  end

  defp step_pulses(pulses, dt) do
    pulses
    |> Enum.map(fn p -> %{p | age: p.age + dt} end)
    |> Enum.reject(fn p -> p.age >= @pulse_ttl end)
  end

  defp draw_pulses(canvas, pulses, width, height) do
    Enum.reduce(pulses, canvas, fn pulse, c ->
      draw_pulse(c, pulse, width, height)
    end)
  end

  defp draw_pulse(canvas, pulse, width, height) do
    progress = pulse.age / @pulse_ttl
    life = (1.0 - progress) * (1.0 - progress)
    ring_r = progress * @pulse_max_radius
    r_int = trunc(ring_r + @pulse_ring_width + 2)

    x0 = trunc(pulse.cx - r_int) |> max(0)
    x1 = trunc(pulse.cx + r_int) |> min(width - 1)
    y0 = trunc(pulse.cy - r_int) |> max(0)
    y1 = trunc(pulse.cy + r_int) |> min(height - 1)

    for x <- x0..x1,
        y <- y0..y1,
        reduce: canvas do
      c ->
        dist = ring_dist(x - pulse.cx, y - pulse.cy)
        band = 1.0 - abs(dist - ring_r) / @pulse_ring_width
        strength = band |> clamp01() |> Kernel.*(band) |> Kernel.*(life) |> Kernel.*(@pulse_strength)

        if strength > 0.02 do
          add_pixel(c, x, y, pulse.color, strength)
        else
          c
        end
    end
  end

  defp ring_dist(dx, dy) do
    :math.sqrt(dx * dx + dy * dy * @y_scale * @y_scale)
  end

  defp draw_people(canvas, people, positions, blink_phase, width, height) do
    Enum.reduce(people, canvas, fn person, c ->
      {sx, sy} = Map.fetch!(positions, person.id)
      x = trunc(sx) |> clamp(0, width - 1)
      y = trunc(sy) |> clamp(0, height - 1)
      phase = Map.get(blink_phase, person.id, 0.0)
      glow = blink_glow(phase, person)
      color = id_color(person.id) |> scale_rgb(glow)
      Canvas.put_pixel(c, {x, y}, color)
    end)
  end

  defp add_pixel(canvas, x, y, color, strength) do
    existing = Canvas.get_pixel(canvas, {x, y})
    rgb = blend_add(existing, color, strength)
    Canvas.put_pixel(canvas, {x, y}, rgb)
  end

  defp blend_add({r1, g1, b1}, {r2, g2, b2}, t) do
    {clamp_byte(r1 + (r2 - r1) * t), clamp_byte(g1 + (g2 - g1) * t), clamp_byte(b1 + (b2 - b1) * t)}
  end

  defp id_color(id) do
    hue = rem(id * 137, 360) / 360.0
    hsl_to_rgb(hue, 0.9, 0.62)
  end

  defp pulse_color(id) do
    {r, g, b} = id_color(id)
    {clamp_byte(r * 0.35 + 160), clamp_byte(g * 0.35 + 160), clamp_byte(b * 0.35 + 160)}
  end

  defp hsl_to_rgb(h, s, l) do
    if s == 0.0 do
      v = clamp_byte(l * 255.0)
      {v, v, v}
    else
      q = if l < 0.5, do: l * (1.0 + s), else: l + s - l * s
      p = 2.0 * l - q

      {hue_to_rgb(p, q, h + 1.0 / 3.0),
       hue_to_rgb(p, q, h),
       hue_to_rgb(p, q, h - 1.0 / 3.0)}
    end
  end

  defp hue_to_rgb(p, q, t) do
    t = if t < 0.0, do: t + 1.0, else: t
    t = if t > 1.0, do: t - 1.0, else: t

    v =
      cond do
        t < 1.0 / 6.0 -> p + (q - p) * 6.0 * t
        t < 1.0 / 2.0 -> q
        t < 2.0 / 3.0 -> p + (q - p) * (2.0 / 3.0 - t) * 6.0
        true -> p
      end

    clamp_byte(v * 255.0)
  end

  defp scale_rgb({r, g, b}, f), do: {clamp_byte(r * f), clamp_byte(g * f), clamp_byte(b * f)}
  defp lerp(a, b, t), do: a + (b - a) * t
  defp clamp(v, lo, hi), do: v |> max(lo) |> min(hi)
  defp clamp_byte(v), do: v |> trunc() |> max(0) |> min(255)
  defp clamp01(v), do: v |> max(0.0) |> min(1.0)
end
