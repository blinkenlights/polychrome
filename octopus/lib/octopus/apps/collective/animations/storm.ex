defmodule Octopus.Apps.Collective.Animations.Storm do
  @moduledoc """
  Tempest — movement triggers lightning; crossing into the installation ring
  (20 m diameter = 10 m radius, matching aframe `panelDiameter`) triggers a
  shooting star on the opposite panel.

  Each person maps to a column on the ring (angular position). Fast movement
  spawns fading lightning bolts at their column. When someone crosses inward
  through the 10 m ring radius, a pale-yellow meteor streaks across the panel
  opposite their entry position.

  Background: `:deep_dark` (black) or `:still_stars` (static starfield).
  """

  @behaviour Octopus.Apps.Collective.Animation

  alias Octopus.Canvas
  alias Octopus.Radar
  alias Octopus.Radar.PanelMapping

  @ref_speed 1.0
  @max_bolt_rate 4.0
  @center_dead_zone 3.0
  @bolt_ttl 0.2

  # Installation ring radius (m): aframe panelDiameter 20 → 10 m radius.
  @entry_radius 10.0

  @meteor_ttl 1.6
  @meteor_trail_len 12

  @bolt_core {210, 225, 255}
  @bolt_glow {60, 80, 150}
  @meteor_head {255, 255, 0}
  @meteor_tail {255, 150, 0}
  @sky_color {6, 10, 26}

  # Moon: wanders horizontally and cycles new → full → new.
  @moon_radius 2.4
  @moon_wander_speed 0.9
  @moon_phase_period 38.0
  @moon_lit {235, 232, 205}
  @moon_dark {26, 30, 48}

  # Satellites: small fast blinking dots near the top.
  @sat_lit {200, 220, 255}

  @panel_width 8

  @activity_floor 0.08
  @activity_gain 0.90
  @activity_cap 0.55
  @bolt_panel_floor 0.25

  @impl true
  def name, do: "Tempest"

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
      bolts: [],
      meteors: [],
      stars: [],
      moon: nil,
      sats: nil,
      prev_radius: %{},
      outside_ids: MapSet.new(),
      radar_seeded: false
    }
  end

  @impl true
  def render(canvas, people, ctx, state) do
    dt = ctx.dt
    width = canvas.width
    height = canvas.height

    stars =
      if state.stars == [] do
        build_stars(width, height)
      else
        state.stars
      end

    moon = step_moon(state.moon || build_moon(width, height), dt, width)
    sats = step_sats(state.sats || build_sats(width, height), dt, width)

    {entries, prev_radius, outside_ids, radar_seeded} =
      if state.radar_seeded do
        entries = detect_radius_entries(people, state.prev_radius, state.outside_ids)
        outside = update_outside_ids(people, state.outside_ids)

        {entries, update_prev_radius(people), outside, true}
      else
        {[], seed_prev_radius(people), update_outside_ids(people, state.outside_ids), true}
      end

    new_meteors = Enum.map(entries, &build_meteor(&1, width, height))

    meteors =
      (state.meteors ++ new_meteors)
      |> step_meteors(dt, height)
      |> Enum.reject(fn m -> m.age >= @meteor_ttl end)

    bleed = Map.get(ctx, :storm_activity_bleed, 0.2) |> clamp01()
    reactivity = Map.get(ctx, :storm_reactivity, 0.5) |> clamp01()

    new_bolts =
      spawn_bolts(people, ctx.sensitivity, dt, width, height, bleed, reactivity)

    bolts =
      (state.bolts ++ new_bolts)
      |> Enum.map(fn b -> %{b | age: b.age + dt} end)
      |> Enum.reject(fn b -> b.age >= @bolt_ttl end)

    bg = Map.get(ctx, :background, :deep_dark)

    canvas =
      canvas
      |> paint_background(bg, stars)
      |> draw_sky_bodies(bg, moon, sats, width)
      |> draw_meteors(meteors)
      |> draw_bolts(bolts)

    {canvas,
     %{
       state
       | bolts: bolts,
         meteors: meteors,
         stars: stars,
         moon: moon,
         sats: sats,
         prev_radius: prev_radius,
         outside_ids: outside_ids,
         radar_seeded: radar_seeded
     }}
  end

  # --- entry detection -----------------------------------------------------

  defp person_radius(%{x: x, y: y}), do: :math.sqrt(x * x + y * y)

  defp seed_prev_radius(people) do
    Map.new(people, fn p -> {p.id, person_radius(p)} end)
  end

  defp update_prev_radius(people) do
    Map.new(people, fn p -> {p.id, person_radius(p)} end)
  end

  defp update_outside_ids(people, outside_ids) do
    Enum.reduce(people, outside_ids, fn p, set ->
      if person_radius(p) > @entry_radius, do: MapSet.put(set, p.id), else: MapSet.delete(set, p.id)
    end)
  end

  defp detect_radius_entries(people, prev_radius, outside_ids) do
    Enum.filter(people, fn p ->
      r = person_radius(p)
      prev = Map.get(prev_radius, p.id)

      crossed =
        prev != nil and prev > @entry_radius and r <= @entry_radius

      from_outside = MapSet.member?(outside_ids, p.id) and r <= @entry_radius

      crossed or from_outside
    end)
  end

  # --- panel geometry (matches aframe) -------------------------------------
  #
  # aframe: 3D panel `t` sits at world angle t/N·2π, position (sin, cos·R).
  # Frame panel `i` (canvas cols i*8..) is shown on 3D panel `N-1-i`
  # (see pixels3daframe.ts: textureIdx = numPanels - i - 1).
  # A person at radar (x, y) → world angle atan2(x, y).

  defp angle_norm(%{x: x, y: y}) do
    a = :math.atan2(x, y)
    :math.fmod(a + 2.0 * :math.pi(), 2.0 * :math.pi()) / (2.0 * :math.pi())
  end

  # Nearest 3D panel index the person is at (their entry panel).
  defp entry_panel_3d(person, num_panels) do
    rem(round(angle_norm(person) * num_panels), num_panels)
  end

  # Frame panel (canvas) index that displays a given 3D panel.
  defp frame_panel_of_3d(t, num_panels), do: num_panels - 1 - t

  # 3D panel directly across the ring from the entry panel.
  defp opposite_3d(entry_t, num_panels), do: rem(entry_t + div(num_panels, 2), num_panels)

  # Frame panel for the meteor (opposite the entry panel).
  defp meteor_frame_panel(person, width) do
    num_panels = div(width, @panel_width)
    entry_t = entry_panel_3d(person, num_panels)
    frame_panel_of_3d(opposite_3d(entry_t, num_panels), num_panels)
  end

  # --- meteors -------------------------------------------------------------

  defp build_meteor(person, width, _height) do
    panel = meteor_frame_panel(person, width)
    x0 = panel * @panel_width
    start_x = x0 + 1.0
    start_y = 0.0

    %{
      x: start_x,
      y: start_y,
      vx: 3.2 + :rand.uniform() * 0.6,
      vy: 3.8 + :rand.uniform() * 0.6,
      age: 0.0,
      trail: [{trunc(start_x), 0}],
      x_min: x0,
      x_max: x0 + @panel_width - 1
    }
  end

  defp step_meteors(meteors, dt, height) do
    Enum.map(meteors, fn m ->
      nx = clamp(m.x + m.vx * dt, m.x_min, m.x_max)
      ny = m.y + m.vy * dt
      point = {trunc(nx), trunc(ny)}

      trail =
        if ny >= 0 and ny < height do
          [point | m.trail] |> Enum.take(@meteor_trail_len)
        else
          m.trail
        end

      %{m | x: nx, y: ny, age: m.age + dt, trail: trail}
    end)
  end

  defp draw_meteors(canvas, meteors) do
    Enum.reduce(meteors, canvas, fn meteor, canvas ->
      life = (1.0 - meteor.age / @meteor_ttl) |> clamp01()
      len = length(meteor.trail)

      meteor.trail
      |> Enum.with_index()
      |> Enum.reduce(canvas, fn {{x, y}, i}, canvas ->
        tail_t = i / max(len - 1, 1)
        # Head (i = 0) is brightest and pure yellow; tail darkens to amber fast.
        brightness = :math.pow(1.0 - tail_t, 1.6) * life
        color = lerp_color(@meteor_tail, @meteor_head, 1.0 - tail_t) |> scale(brightness)

        if i == 0 do
          draw_head(canvas, {x, y}, color, life)
        else
          put_pixel(canvas, {x, y}, color)
        end
      end)
    end)
  end

  # Bigger, defined head: a 2x2 full-colour core plus a bloom on the leading
  # edge (moving toward +x / +y, i.e. down-right).
  defp draw_head(canvas, {x, y}, color, life) do
    core = color
    glow = scale(@meteor_head, 0.4 * life)

    canvas
    |> put_pixel({x, y}, core)
    |> put_pixel({x + 1, y}, core)
    |> put_pixel({x, y + 1}, core)
    |> put_pixel({x + 1, y + 1}, core)
    |> put_pixel({x + 2, y + 1}, glow)
    |> put_pixel({x + 1, y + 2}, glow)
    |> put_pixel({x - 1, y}, scale(color, 0.5))
    |> put_pixel({x, y - 1}, scale(color, 0.5))
  end

  # --- background ----------------------------------------------------------

  defp paint_background(canvas, :deep_dark, _stars), do: Canvas.fill(canvas, {0, 0, 0})

  defp paint_background(canvas, :still_stars, stars) do
    canvas = Canvas.fill(canvas, @sky_color)
    Enum.reduce(stars, canvas, fn s, c -> Canvas.put_pixel(c, {s.x, s.y}, s.color) end)
  end

  # --- moon + satellites ---------------------------------------------------

  defp build_moon(width, height) do
    %{
      x: :rand.uniform() * width,
      y: 1.5 + :rand.uniform() * max(height - 4, 1),
      phase: :rand.uniform()
    }
  end

  defp step_moon(moon, dt, width) do
    %{
      moon
      | x: :math.fmod(moon.x + @moon_wander_speed * dt + width, width),
        phase: :math.fmod(moon.phase + dt / @moon_phase_period, 1.0)
    }
  end

  defp build_sats(width, height) do
    for _ <- 1..:rand.uniform(2) do
      dir = if :rand.uniform() < 0.5, do: -1.0, else: 1.0

      %{
        x: :rand.uniform() * width,
        y: :rand.uniform(max(div(height, 2), 1)) - 1,
        vx: dir * (4.5 + :rand.uniform() * 3.0),
        blink: :rand.uniform() * 6.28,
        blink_rate: 2.0 + :rand.uniform() * 2.0
      }
    end
  end

  defp step_sats(sats, dt, width) do
    Enum.map(sats, fn s ->
      %{
        s
        | x: :math.fmod(s.x + s.vx * dt + width, width),
          blink: s.blink + s.blink_rate * dt
      }
    end)
  end

  defp draw_sky_bodies(canvas, :still_stars, moon, sats, width) do
    canvas
    |> draw_moon(moon, width)
    |> draw_sats(sats, width)
  end

  defp draw_sky_bodies(canvas, _bg, _moon, _sats, _width), do: canvas

  defp draw_moon(canvas, moon, width) do
    r = @moon_radius
    cosa = :math.cos(2.0 * :math.pi() * moon.phase)
    waxing = moon.phase <= 0.5
    ri = ceil(r)

    for dy <- -ri..ri, dx <- -ri..ri, reduce: canvas do
      canvas ->
        if dx * dx + dy * dy <= r * r do
          limb = :math.sqrt(max(r * r - dy * dy, 0.0))
          xt = cosa * limb
          lit = if waxing, do: dx >= xt, else: dx <= -xt

          color =
            if lit do
              edge = 1.0 - (dx * dx + dy * dy) / (r * r) * 0.35
              scale(@moon_lit, clamp01(edge))
            else
              @moon_dark
            end

          px = round(:math.fmod(moon.x + dx + width, width))
          put_pixel(canvas, {px, round(moon.y) + dy}, color)
        else
          canvas
        end
    end
  end

  defp draw_sats(canvas, sats, width) do
    Enum.reduce(sats, canvas, fn s, canvas ->
      b = 0.55 + 0.45 * :math.sin(s.blink)
      color = scale(@sat_lit, clamp01(b))
      x = round(s.x)
      tail = round(:math.fmod(s.x - sign(s.vx) + width, width))

      canvas
      |> put_pixel({x, round(s.y)}, color)
      |> put_pixel({tail, round(s.y)}, scale(color, 0.3))
    end)
  end

  defp sign(v) when v < 0, do: -1.0
  defp sign(_), do: 1.0

  defp build_stars(width, height) do
    count = max(div(width * height, 22), 12)

    for _ <- 1..count do
      b = 0.45 + :rand.uniform() * 0.55
      %{
        x: :rand.uniform(width) - 1,
        y: :rand.uniform(height) - 1,
        color: {trunc(b * 150), trunc(b * 170), trunc(b * 215)}
      }
    end
  end

  # --- panel activity (W channel + bolt crowd weight) ----------------------

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

  # --- lightning -----------------------------------------------------------

  defp spawn_bolts(people, sensitivity, dt, width, height, bleed, reactivity) do
    num_panels = max(div(width, @panel_width), 1)
    levels = frame_activity_levels(num_panels, bleed)

    Enum.flat_map(people, fn p ->
      radius = :math.sqrt(p.x * p.x + p.y * p.y)
      speed = :math.sqrt(p.vx * p.vx + p.vy * p.vy)

      cond do
        radius < @center_dead_zone ->
          []

        :rand.uniform() < bolt_spawn_prob(speed, sensitivity, dt, p, width, levels, reactivity) ->
          [build_bolt(person_bolt_column(p, width), height)]

        true ->
          []
      end
    end)
  end

  defp bolt_spawn_prob(speed, sensitivity, dt, person, width, levels, reactivity) do
    base = spawn_prob(speed, sensitivity, dt)
    panel_level = person_panel_level(person, width, levels)
    target = max(panel_level, @bolt_panel_floor)
    crowd_mult = lerp(1.0, target, reactivity)
    base * crowd_mult
  end

  defp person_panel_level(person, width, levels) do
    num_panels = div(width, @panel_width)
    frame_panel = frame_panel_of_3d(entry_panel_3d(person, num_panels), num_panels)
    Map.get(levels, frame_panel, 0.0)
  end

  defp spawn_prob(speed, sensitivity, dt) do
    (speed / @ref_speed) |> clamp01() |> Kernel.*(@max_bolt_rate * sensitivity * dt)
  end

  # Bolt at the centre of the person's own (entry) frame panel.
  defp person_bolt_column(person, width) do
    num_panels = div(width, @panel_width)
    frame_panel = frame_panel_of_3d(entry_panel_3d(person, num_panels), num_panels)
    frame_panel * @panel_width + div(@panel_width, 2)
  end

  defp build_bolt(start_x, height) do
    {points, _} =
      Enum.map_reduce(0..(height - 1), start_x, fn y, x ->
        nx = x + (:rand.uniform(3) - 2)
        {{nx, y}, nx}
      end)

    %{points: points, age: 0.0}
  end

  defp draw_bolts(canvas, bolts) do
    Enum.reduce(bolts, canvas, fn bolt, canvas ->
      b = (1.0 - bolt.age / @bolt_ttl) |> clamp01()
      core = scale(@bolt_core, b)
      glow = scale(@bolt_glow, b)

      Enum.reduce(bolt.points, canvas, fn {x, y}, canvas ->
        canvas
        |> blend_pixel({x, y}, core)
        |> blend_pixel({x - 1, y}, glow)
        |> blend_pixel({x + 1, y}, glow)
      end)
    end)
  end

  # --- drawing helpers -----------------------------------------------------

  defp put_pixel(%Canvas{width: w, height: h} = canvas, {x, y}, color)
       when x >= 0 and y >= 0 and x < w and y < h do
    Canvas.put_pixel(canvas, {x, y}, color)
  end

  defp put_pixel(canvas, _coord, _color), do: canvas

  defp blend_pixel(%Canvas{width: w, height: h} = canvas, {x, y}, color)
       when x >= 0 and y >= 0 and x < w and y < h do
    existing = Canvas.get_pixel(canvas, {x, y})
    Canvas.put_pixel(canvas, {x, y}, add(existing, color))
  end

  defp blend_pixel(canvas, _coord, _color), do: canvas

  defp lerp_color({r1, g1, b1}, {r2, g2, b2}, t) do
    {lerp(r1, r2, t), lerp(g1, g2, t), lerp(b1, b2, t)}
  end

  defp lerp(a, b, t), do: a + (b - a) * t

  defp add({r1, g1, b1}, {r2, g2, b2}) do
    {min(r1 + r2, 255), min(g1 + g2, 255), min(b1 + b2, 255)}
  end

  defp scale({r, g, b}, f), do: {trunc(r * f), trunc(g * f), trunc(b * f)}

  defp clamp(value, lo, hi), do: value |> max(lo) |> min(hi)

  defp clamp01(value), do: value |> max(0.0) |> min(1.0)
end
