defmodule Octopus.Apps.Collective.Animations.Orbital do
  @moduledoc """
  Orbital — the crowd as a living solar system.

  * **Sun** — people in the 2 m center disk drive a warm glow in the upper sky.
  * **Planets** — ring walkers appear as comet heads with motion trails on the
    lower strip (angular position on x, radius on y — same mapping as Crowd Dots).
  * **Groups** — 3+ ring people within ~2.5 m merge into one larger body at their
    centroid; singletons stay small.
  * **Stars** — sparse background; the field drifts slightly with the ring crowd's
    angular centroid (balance / imbalance of the crowd).
  """

  @behaviour Octopus.Apps.Collective.Animation

  alias Octopus.Canvas
  alias Octopus.Radar.PanelMapping

  @panel_width 8
  @center_radius 2.0
  @group_dist_sq 2.5 * 2.5
  @group_min 3

  @bg {4, 6, 18}
  @star {140, 155, 200}
  @sun_core {255, 245, 210}
  @sun_glow {255, 190, 70}
  @sun_ray {80, 55, 25}

  @trail_len 5
  @move_speed 0.15

  @impl true
  def name, do: "Orbital"

  @impl true
  def init(display_info) do
    width = display_info.width
    height = display_info.height

    %{
      positions: %{},
      trails: %{},
      stars: build_stars(width, height),
      sun_level: 0.0,
      drift: 0.0,
      t: 0.0
    }
  end

  @impl true
  def render(canvas, people, ctx, state) do
    dt = ctx.dt
    width = canvas.width
    height = canvas.height
    num_panels = max(div(width, @panel_width), 1)
    ring_outer = PanelMapping.ring_radius()

    liveliness = Map.get(ctx, :orbital_liveliness, 0.35) |> clamp01()
    sun_gain = Map.get(ctx, :orbital_sun_gain, 1.0) |> max(0.2)

    smooth = lerp(0.08, 0.28, liveliness)
    alpha = 1.0 - :math.exp(-dt / smooth)
    sun_tau = lerp(2.5, 0.8, liveliness)
    sun_alpha = 1.0 - :math.exp(-dt / sun_tau)

    t = state.t + dt

    {center, ring} = split_people(people)
    bodies = ring_bodies(ring)

    sun_target = center_level(center) * sun_gain
    sun_level = state.sun_level + (sun_target - state.sun_level) * sun_alpha

    drift_target = ring_drift(ring, width, num_panels)
    drift = state.drift + (drift_target - state.drift) * alpha

    {positions, trails} =
      step_bodies(bodies, state.positions, state.trails, num_panels, height, ring_outer, alpha)

    canvas =
      canvas
      |> Canvas.fill(@bg)
      |> draw_stars(state.stars, drift, width)
      |> draw_sun(center, sun_level, liveliness, t, width, height, num_panels)
      |> draw_bodies(bodies, positions, trails, width, height)

    {canvas, %{state | positions: positions, trails: trails, sun_level: sun_level, drift: drift, t: t}}
  end

  # --- people / bodies -----------------------------------------------------

  defp split_people(people) do
    Enum.split_with(people, fn p ->
      PanelMapping.track_radius(p) < @center_radius
    end)
  end

  defp ring_bodies(ring_people) do
    {clusters, _assigned} =
      Enum.reduce(ring_people, {[], MapSet.new()}, fn person, {clusters_acc, assigned} ->
        if MapSet.member?(assigned, person.id) do
          {clusters_acc, assigned}
        else
          members =
            Enum.filter(ring_people, fn other ->
              not MapSet.member?(assigned, other.id) and
                dist_sq(person, other) <= @group_dist_sq
            end)

          ids = MapSet.new(members, & &1.id)
          assigned = MapSet.union(assigned, ids)

          body =
            if length(members) >= @group_min do
              %{kind: :group, members: members, id: group_id(members)}
            else
              %{kind: :solo, members: [person], id: person.id}
            end

          {[body | clusters_acc], assigned}
        end
      end)

    clusters
  end

  defp group_id(members) do
    members
    |> Enum.map(& &1.id)
    |> Enum.sort()
    |> Enum.reduce(0, fn id, acc -> acc * 31 + id end)
  end

  defp dist_sq(a, b), do: (a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)

  defp body_world(body) do
    n = length(body.members)

    {sx, sy, svx, svy} =
      Enum.reduce(body.members, {0.0, 0.0, 0.0, 0.0}, fn p, {x, y, vx, vy} ->
        {x + p.x, y + p.y, vx + p.vx, vy + p.vy}
      end)

    inv = 1.0 / n
    %{x: sx * inv, y: sy * inv, vx: svx * inv, vy: svy * inv}
  end

  defp step_bodies(bodies, positions, trails, num_panels, height, ring_outer, alpha) do
    active_ids = MapSet.new(bodies, & &1.id)

    {positions, trails} =
      Enum.reduce(bodies, {positions, trails}, fn body, {pos_acc, trail_acc} ->
        world = body_world(body)
        person = %{id: body.id, x: world.x, y: world.y, vx: world.vx, vy: world.vy}
        target = person_canvas_xy(person, num_panels, height, ring_outer)
        {sx, sy} = Map.get(pos_acc, body.id, target)
        sx = sx + (elem(target, 0) - sx) * alpha
        sy = sy + (elem(target, 1) - sy) * alpha
        pos_acc = Map.put(pos_acc, body.id, {sx, sy})

        point = {trunc(sx), trunc(sy)}

        trail =
          trail_acc
          |> Map.get(body.id, [])
          |> maybe_prepend_trail(point, person)
          |> Enum.take(@trail_len)

        trail_acc = Map.put(trail_acc, body.id, trail)
        {pos_acc, trail_acc}
      end)

    positions = Map.take(positions, MapSet.to_list(active_ids))
    trails = Map.take(trails, MapSet.to_list(active_ids))
    {positions, trails}
  end

  defp maybe_prepend_trail(trail, point, person) do
    if PanelMapping.track_speed(person) > @move_speed do
      case trail do
        [^point | _] -> trail
        _ -> [point | trail]
      end
    else
      trail
    end
  end

  defp center_level([]), do: 0.0

  defp center_level(center) do
    count = (length(center) / 5.0) |> clamp01()
    activity = (avg_speed(center) / 0.65) |> clamp01()
    clamp01(0.5 * count + 0.5 * activity)
  end

  defp ring_drift([], _width, _num_panels), do: 0.0

  defp ring_drift(ring, width, num_panels) do
    cols =
      Enum.map(ring, fn p ->
        person_column_f(p, num_panels)
      end)

    avg = Enum.sum(cols) / length(cols)
    (avg / max(width - 1, 1) - 0.5) * width * 0.08
  end

  # --- drawing -------------------------------------------------------------

  defp draw_stars(canvas, stars, drift, width) do
    Enum.reduce(stars, canvas, fn s, c ->
      x = trunc(:math.fmod(s.x + drift + width, width))
      Canvas.put_pixel(c, {x, s.y}, scale(@star, s.brightness))
    end)
  end

  defp draw_sun(canvas, center, sun_level, liveliness, t, width, height, num_panels) do
    if sun_level < 0.02 and center == [] do
      canvas
    else
      sun_x =
        if center == [] do
          width / 2.0
        else
          cols = Enum.map(center, &person_column_f(&1, num_panels))
          Enum.sum(cols) / length(cols)
        end

      sun_y = 1.0 + :math.sin(t * lerp(0.4, 1.2, liveliness)) * 0.25
      core_r = lerp(0.8, 2.2, sun_level)
      glow_r = core_r + lerp(1.0, 2.8, sun_level)

      canvas
      |> draw_disc(sun_x, sun_y, glow_r, scale(@sun_glow, 0.35 * sun_level), width, height)
      |> draw_disc(sun_x, sun_y, core_r, scale(@sun_core, 0.55 + 0.45 * sun_level), width, height)
      |> draw_sun_rays(center, sun_level, t, width, height, num_panels)
    end
  end

  defp draw_sun_rays(canvas, center, sun_level, t, width, height, num_panels) do
    if sun_level < 0.15 or center == [] do
      canvas
    else
      Enum.reduce(center, canvas, fn person, c ->
        col = person_column_f(person, num_panels)
        speed = PanelMapping.track_speed(person)
        strength = clamp01(sun_level * (0.4 + speed * 0.6))
        y0 = 2
        y1 = min(trunc(height / 2), 4)
        flicker = 0.65 + 0.35 * :math.sin(t * 4.0 + person.id)

        Enum.reduce(y0..y1, c, fn y, acc ->
          fade = (y - y0 + 1) / max(y1 - y0 + 1, 1)
          color = scale(@sun_ray, strength * flicker * fade * 0.5)
          add_pixel(acc, trunc(col), y, color, width, height)
        end)
      end)
    end
  end

  defp draw_bodies(canvas, bodies, positions, trails, width, height) do
    Enum.reduce(bodies, canvas, fn body, c ->
      {sx, sy} = Map.fetch!(positions, body.id)
      trail = Map.get(trails, body.id, [])
      size = if body.kind == :group, do: 2, else: 1
      color = body_color(body)
      glow = scale(color, 0.45)

      c
      |> draw_trail(trail, color, width, height)
      |> draw_comet(trunc(sx), trunc(sy), size, color, glow, width, height)
    end)
  end

  defp draw_trail(canvas, trail, color, width, height) do
    len = length(trail)

    trail
    |> Enum.with_index()
    |> Enum.reduce(canvas, fn {{x, y}, i}, c ->
      t = i / max(len - 1, 1)
      brightness = :math.pow(1.0 - t, 1.4) * 0.7
      add_pixel(c, x, y, scale(color, brightness), width, height)
    end)
  end

  defp draw_comet(canvas, x, y, size, color, glow, width, height) do
    canvas
    |> draw_bloom(x, y, size, color, glow, width, height)
  end

  defp draw_bloom(canvas, x, y, size, core, glow, width, height) do
    offsets =
      if size >= 2 do
        for dx <- -1..1, dy <- -1..1, do: {dx, dy}
      else
        [{0, 0}, {1, 0}, {0, 1}, {-1, 0}, {0, -1}]
      end

    canvas =
      Enum.reduce(offsets, canvas, fn {dx, dy}, c ->
        add_pixel(c, x + dx, y + dy, glow, width, height)
      end)

    add_pixel(canvas, x, y, core, width, height)
  end

  defp draw_disc(canvas, cx, cy, radius, color, width, height) do
    r = ceil(radius)

    for dy <- -r..r, dx <- -r..r, reduce: canvas do
      c ->
        d = :math.sqrt(dx * dx + dy * dy)

        if d <= radius do
          falloff = 1.0 - d / max(radius, 0.001)
          add_pixel(c, trunc(cx + dx), trunc(cy + dy), scale(color, falloff), width, height)
        else
          c
        end
    end
  end

  defp add_pixel(canvas, x, y, color, width, height) do
    if x >= 0 and x < width and y >= 0 and y < height do
      existing = Canvas.get_pixel(canvas, {x, y})
      Canvas.put_pixel(canvas, {x, y}, blend_add(existing, color))
    else
      canvas
    end
  end

  defp blend_add({r1, g1, b1}, {r2, g2, b2}) do
    {clamp_byte(r1 + r2), clamp_byte(g1 + g2), clamp_byte(b1 + b2)}
  end

  # --- geometry (matches Crowd Dots / PanelMapping) -------------------------

  defp person_canvas_xy(person, num_panels, height, ring_outer) do
    col = person_column_f(person, num_panels)
    row = PanelMapping.radius_to_canvas_row(PanelMapping.track_radius(person), height, ring_outer)
    {col, row}
  end

  defp person_column_f(person, num_panels) do
    norm = PanelMapping.angle_norm(person)
    total = norm * num_panels * @panel_width
    sim_panel = min(trunc(total / @panel_width), num_panels - 1)
    within = total - sim_panel * @panel_width
    frame_panel = PanelMapping.frame_panel_of_3d(sim_panel, num_panels)
    frame_panel * @panel_width + within
  end

  # --- stars ---------------------------------------------------------------

  defp build_stars(width, height) do
    count = max(trunc(width / 18), 12)

    for _ <- 1..count do
      %{
        x: :rand.uniform(max(width, 1)) - 1,
        y: :rand.uniform(max(trunc(height / 2), 1)) - 1,
        brightness: 0.25 + :rand.uniform() * 0.75
      }
    end
  end

  defp body_color(%{kind: :group, id: id}), do: id_color(id, 0.55, 0.72)
  defp body_color(%{kind: :solo, members: [%{id: id}]}), do: id_color(id, 0.85, 0.62)

  defp id_color(id, sat, lit) do
    hue = rem(id * 137, 360) / 360.0
    hsl_to_rgb(hue, sat, lit)
  end

  defp avg_speed(people) do
    {sum, n} =
      Enum.reduce(people, {0.0, 0}, fn p, {s, c} ->
        {s + PanelMapping.track_speed(p), c + 1}
      end)

    sum / n
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

  defp scale({r, g, b}, t) do
    {clamp_byte(r * t), clamp_byte(g * t), clamp_byte(b * t)}
  end

  defp lerp(a, b, t), do: a + (b - a) * t
  defp clamp_byte(v), do: v |> trunc() |> max(0) |> min(255)
  defp clamp01(v), do: v |> max(0.0) |> min(1.0)
end
