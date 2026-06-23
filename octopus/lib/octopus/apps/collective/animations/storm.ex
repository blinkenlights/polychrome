defmodule Octopus.Apps.Collective.Animations.Storm do
  @moduledoc """
  Tempest — movement triggers lightning; crossing into the installation ring
  (18 m diameter = 9 m radius, matching aframe `panelDiameter`) triggers a
  shooting star on the opposite panel.

  Each person maps to a column on the ring (angular position). Fast movement
  spawns fading lightning bolts at their column. When someone crosses inward
  through the 9 m ring radius, a pale-yellow meteor streaks across the panel
  opposite their entry position.

  Background: `:deep_dark` (black) or `:still_stars` (static starfield).
  """

  @behaviour Octopus.Apps.Collective.Animation

  alias Octopus.Canvas

  @ref_speed 1.0
  @max_bolt_rate 4.0
  @center_dead_zone 3.0
  @bolt_ttl 0.2

  # Installation ring radius (m): aframe panelDiameter 18 → 9 m radius.
  @entry_radius 9.0

  @meteor_ttl 0.85
  @meteor_trail_len 8

  @bolt_core {210, 225, 255}
  @bolt_glow {60, 80, 150}
  @meteor_head {255, 255, 0}
  @meteor_tail {255, 150, 0}
  @sky_color {6, 10, 26}

  @panel_width 8

  @impl true
  def name, do: "Tempest"

  @impl true
  def init(_display_info) do
    %{
      bolts: [],
      meteors: [],
      stars: [],
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

    new_bolts = spawn_bolts(people, ctx.sensitivity, dt, width, height)

    bolts =
      (state.bolts ++ new_bolts)
      |> Enum.map(fn b -> %{b | age: b.age + dt} end)
      |> Enum.reject(fn b -> b.age >= @bolt_ttl end)

    canvas =
      canvas
      |> paint_background(Map.get(ctx, :background, :deep_dark), stars)
      |> draw_meteors(meteors)
      |> draw_bolts(bolts)

    {canvas,
     %{
       state
       | bolts: bolts,
         meteors: meteors,
         stars: stars,
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
      vx: 6.5 + :rand.uniform() * 1.0,
      vy: 7.5 + :rand.uniform() * 1.0,
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

  # Bright, defined head: full-colour core with a tight bloom on the leading edge
  # (moving toward +x / +y, i.e. down-right), no wide halo.
  defp draw_head(canvas, {x, y}, color, life) do
    glow = scale(@meteor_head, 0.35 * life)

    canvas
    |> put_pixel({x, y}, color)
    |> put_pixel({x + 1, y}, glow)
    |> put_pixel({x, y + 1}, glow)
  end

  # --- background ----------------------------------------------------------

  defp paint_background(canvas, :deep_dark, _stars), do: Canvas.fill(canvas, {0, 0, 0})

  defp paint_background(canvas, :still_stars, stars) do
    canvas = Canvas.fill(canvas, @sky_color)
    Enum.reduce(stars, canvas, fn s, c -> Canvas.put_pixel(c, {s.x, s.y}, s.color) end)
  end

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

  # --- lightning -----------------------------------------------------------

  defp spawn_bolts(people, sensitivity, dt, width, height) do
    Enum.flat_map(people, fn p ->
      radius = :math.sqrt(p.x * p.x + p.y * p.y)
      speed = :math.sqrt(p.vx * p.vx + p.vy * p.vy)

      cond do
        radius < @center_dead_zone ->
          []

        :rand.uniform() < spawn_prob(speed, sensitivity, dt) ->
          [build_bolt(person_bolt_column(p, width), height)]

        true ->
          []
      end
    end)
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
