defmodule Octopus.Apps.Collective.Animations.Breath do
  @moduledoc """
  Crowd Breath — slow travelling wave with locally tinted colour.

  Wave shape is global (density + activity); colour follows each person on the
  strip with a soft falloff. Tuned for a calm, meditative feel — heavy temporal
  smoothing and slow drift speeds.
  """

  @behaviour Octopus.Apps.Collective.Animation

  @full_count 10

  @panel_width 8
  @color_radius 14

  @cycles_swell 2
  @cycles_mid 3
  @cycles_ripple 5
  @spd_swell 0.06
  @spd_mid 0.09
  @spd_ripple 0.12
  @spd_counter 0.07

  @default_color {8, 18, 32}

  # Canopy sky: soft white-green → pure white (center-driven).
  @canopy_sky_stops {{185, 255, 175}, {235, 255, 245}, {255, 255, 255}}

  # {calm, mid, hot} — still → moving along each preset's arc.
  @palettes %{
    ocean: {{20, 70, 150}, {30, 170, 110}, {235, 180, 45}},
    ember: {{55, 18, 12}, {175, 55, 18}, {255, 145, 35}},
    aurora: {{35, 12, 75}, {15, 155, 175}, {75, 250, 115}},
    violet: {{28, 18, 88}, {135, 38, 158}, {255, 95, 175}},
    mono: {{25, 30, 42}, {88, 94, 104}, {208, 214, 222}}
  }

  @impl true
  def name, do: "Crowd Breath"

  # People inside the installation's 2 m center chill disk (no ring column).
  @center_radius 2.0

  @impl true
  def init(_display_info) do
    %{t: 0.0, density: 0.0, activity: 0.0, center_level: 0.0, heat: %{}}
  end

  @impl true
  def render(canvas, people, ctx, state) do
    liv = Map.get(ctx, :breath_liveliness, 0.25) |> clamp01()
    dt = ctx.dt

    tau = lerp(4.5, 1.0, liv)
    heat_tau = lerp(6.0, 1.2, liv)
    full_speed = lerp(0.65, 0.3, liv)

    alpha = 1.0 - :math.exp(-dt / tau)
    heat_alpha = 1.0 - :math.exp(-dt / heat_tau)

    density_target = (length(people) / @full_count) |> clamp01()
    density = state.density + (density_target - state.density) * alpha

    activity_target = (avg_speed(people) / full_speed) |> clamp01()
    activity = state.activity + (activity_target - state.activity) * alpha

    t = state.t + dt
    width = ctx.display_info.width

    target_heat = column_heat(width, people, full_speed)
    heat = smooth_heat(state.heat, target_heat, width, heat_alpha)

    palette = Map.get(ctx, :breath_palette, :ocean)
    hue_shift = Map.get(ctx, :breath_hue_shift, 0.0) |> clamp01()
    layout = Map.get(ctx, :breath_layout, :wave)
    stops = palette_stops(palette, hue_shift)
    sky_stops = @canopy_sky_stops

    center_target = center_level(people, full_speed)
    center_level_sm =
      state.center_level + (center_target - state.center_level) * alpha

    canvas = paint(canvas, t, density, activity, heat, liv, layout, stops, sky_stops, center_level_sm)

    {canvas,
     %{
       state
       | t: t,
         density: density,
         activity: activity,
         heat: heat,
         center_level: center_level_sm
     }}
  end

  defp avg_speed([]), do: 0.0

  defp avg_speed(people) do
    {sum, n} =
      Enum.reduce(people, {0.0, 0}, fn p, {s, c} ->
        {s + :math.sqrt(p.vx * p.vx + p.vy * p.vy), c + 1}
      end)

    sum / n
  end

  defp smooth_heat(old, target, width, alpha) do
    for x <- 0..(width - 1), into: %{} do
      t = Map.get(target, x, 0.0)
      o = Map.get(old, x, 0.0)
      {x, o + (t - o) * alpha}
    end
  end

  defp center_level(people, full_speed) do
    center =
      Enum.filter(people, fn p ->
        p.x * p.x + p.y * p.y < @center_radius * @center_radius
      end)

    count = (length(center) / 5.0) |> clamp01()
    activity = (avg_speed(center) / full_speed) |> clamp01()
    clamp01(0.55 * count + 0.45 * activity)
  end

  defp paint(canvas, t, density, activity, heat, liv, :canopy, stops, sky_stops, center_level) do
    paint_canopy(canvas, t, density, activity, heat, liv, stops, sky_stops, center_level)
  end

  defp paint(canvas, t, density, activity, heat, liv, _layout, stops, _sky_stops, _center_level) do
    paint_wave(canvas, t, density, activity, heat, liv, stops)
  end

  defp paint_wave(canvas, t, density, activity, heat, liv, {calm, mid, hot}) do
    height = canvas.height
    width = canvas.width

    ks = 2.0 * :math.pi() * @cycles_swell / width
    km = 2.0 * :math.pi() * @cycles_mid / width
    kr = 2.0 * :math.pi() * @cycles_ripple / width

    wave_mul = lerp(0.6, 2.8, liv)

    w_swell = 0.7 * (1.0 - density)
    w_mid = 0.45
    w_ripple = lerp(0.08, 0.2, liv) + lerp(0.35, 0.75, liv) * density
    w_counter = lerp(0.04, 0.12, liv) + lerp(0.2, 0.75, liv) * activity
    wsum = w_swell + w_mid + w_ripple + w_counter

    waterline = lerp(0.12, 0.55, density)
    amplitude = lerp(0.04, 0.42, density)
    speed = lerp(lerp(0.08, 0.25, liv), lerp(0.45, 1.6, liv), activity)

    surfaces =
      for x <- 0..(width - 1), into: %{} do
        wave =
          (w_swell * :math.sin(ks * x - @spd_swell * wave_mul * speed * t) +
             w_mid * :math.sin(km * x - @spd_mid * wave_mul * speed * t + 0.7) +
             w_ripple * :math.sin(kr * x - @spd_ripple * wave_mul * speed * t) +
             w_counter * :math.sin(km * x + @spd_counter * wave_mul * speed * t)) / wsum

        fill = clamp01(waterline + amplitude * wave)
        {x, fill * height}
      end

    for x <- 0..(width - 1), y <- 0..(height - 1), into: canvas do
      surface = Map.fetch!(surfaces, x)
      rows_from_bottom = height - 1 - y
      coverage = coverage(rows_from_bottom, surface)

      presence = Map.fetch!(heat, x)
      base = lerp_color(@default_color, color_for(presence, calm, mid, hot), presence)

      depth = rows_from_bottom / max(surface, 1.0)
      brightness = 0.35 + 0.65 * clamp01(depth) * presence

      {{x, y}, scale(base, coverage * brightness)}
    end
  end

  # Canopy: dark at the physical top & bottom, bright glowing horizon at the
  # split (best from the center). Ring palette below, neon sky above; both fade
  # to black toward the edges and peak where they meet.
  defp paint_canopy(canvas, t, density, activity, heat, liv, stops, sky_stops, center_level) do
    height = canvas.height
    width = canvas.width
    mid_y = (height - 1) / 2.0
    half_h = mid_y

    horizons =
      for x <- 0..(width - 1), into: %{} do
        wave = horizon_wave(x, width, t, activity, liv)
        {x, mid_y + wave * lerp(0.15, 0.5, density)}
      end

    glow = clamp01(max(center_level * 1.15, 0.25))
    {sky_calm, sky_mid, sky_hot} = sky_stops
    {ring_calm, ring_mid, ring_hot} = stops

    for x <- 0..(width - 1), y <- 0..(height - 1), into: canvas do
      horizon = Map.fetch!(horizons, x)
      presence = Map.fetch!(heat, x)

      {falloff, side} =
        if y >= horizon do
          {edge_falloff(y - horizon, height - 1 - horizon), :sky}
        else
          {edge_falloff(horizon - y, horizon), :ring}
        end

      base =
        case side do
          :sky ->
            color_for(glow, sky_calm, sky_mid, sky_hot)

          :ring ->
            color_for(presence, ring_calm, ring_mid, ring_hot)
        end

      # Extra punch on the horizon seam (both sides contribute).
      seam = seam_boost(y, horizon, half_h)

      {{x, y},
       scale(
         lerp_color(@default_color, base, clamp01(falloff * 0.85 + seam * 0.28)),
         clamp01(falloff + seam * 0.35)
       )}
    end
  end

  # Wobble the horizon line slowly around the ring.
  defp horizon_wave(x, width, t, activity, liv) do
    ks = 2.0 * :math.pi() * @cycles_mid / width
    km = 2.0 * :math.pi() * @cycles_swell / width
    speed = lerp(0.08, 0.5, activity) * lerp(0.6, 1.8, liv)

    0.6 * :math.sin(ks * x - @spd_mid * speed * t) +
      0.4 * :math.sin(km * x - @spd_swell * speed * t + 0.5)
  end

  # 1 at the near edge (horizon), 0 at the far edge (top or ground).
  defp edge_falloff(dist, span) do
    t = clamp01(dist / max(span, 0.5) * 1.15)
    :math.cos(t * :math.pi() / 2)
  end

  # Bright band straddling the horizon (physical middle of the panel).
  defp seam_boost(y, horizon, half_h) do
    d = abs(y - horizon) / max(half_h * 0.32, 0.5)
    max(0.0, 1.0 - d * d)
  end

  defp column_heat(width, people, full_speed) do
    base = for x <- 0..(width - 1), into: %{}, do: {x, 0.0}

    ring =
      Enum.filter(people, fn p ->
        p.x * p.x + p.y * p.y >= @center_radius * @center_radius
      end)

    Enum.reduce(ring, base, fn p, acc ->
      col = person_column(p, width)
      intensity = (:math.sqrt(p.vx * p.vx + p.vy * p.vy) / full_speed) |> clamp01()
      add_heat(acc, col, intensity, width)
    end)
  end

  defp add_heat(acc, center, intensity, width) do
    Enum.reduce(-@color_radius..@color_radius, acc, fn offset, acc ->
      x = wrap_col(center + offset, width)
      dist = abs(offset)
      weight = max(0.0, :math.cos(dist / (@color_radius + 1) * :math.pi() / 2))
      current = Map.fetch!(acc, x)
      Map.put(acc, x, clamp01(current + intensity * weight))
    end)
  end

  defp wrap_col(x, width), do: rem(rem(x, width) + width, width)

  defp person_column(%{x: x, y: y}, width) do
    angle = :math.atan2(x, y)
    norm = :math.fmod(angle + 2.0 * :math.pi(), 2.0 * :math.pi()) / (2.0 * :math.pi())

    num_panels = div(width, @panel_width)
    total = norm * width
    sim_panel = min(trunc(total / @panel_width), num_panels - 1)
    within = total - sim_panel * @panel_width

    frame_panel = num_panels - 1 - sim_panel
    trunc(frame_panel * @panel_width + within) |> clamp(0, width - 1)
  end

  defp coverage(rows_from_bottom, surface) do
    cond do
      rows_from_bottom + 1 <= surface -> 1.0
      rows_from_bottom < surface -> surface - rows_from_bottom
      true -> 0.0
    end
  end

  defp palette_stops(palette, hue_shift) do
    {calm, mid, hot} = Map.get(@palettes, palette, @palettes.ocean)
    degrees = hue_shift * 360.0
    {hue_rotate(calm, degrees), hue_rotate(mid, degrees), hue_rotate(hot, degrees)}
  end

  defp color_for(intensity, calm, mid, hot) do
    if intensity < 0.5 do
      lerp_color(calm, mid, intensity * 2.0)
    else
      lerp_color(mid, hot, (intensity - 0.5) * 2.0)
    end
  end

  # Rotate RGB around the hue wheel; saturation/lightness preserved.
  defp hue_rotate({r, g, b}, degrees) do
    {h, s, l} = rgb_to_hsl(r / 255.0, g / 255.0, b / 255.0)
    h2 = :math.fmod(h + degrees / 360.0 + 1.0, 1.0)
    hsl_to_rgb(h2, s, l)
  end

  defp rgb_to_hsl(r, g, b) do
    max = max(r, max(g, b))
    min = min(r, min(g, b))
    l = (max + min) / 2.0

    {h, s} =
      if max == min do
        {0.0, 0.0}
      else
        d = max - min

        s =
          if l > 0.5,
            do: d / (2.0 - max - min),
            else: d / (max + min)

        h =
          cond do
            max == r -> (g - b) / d + if(g < b, do: 6.0, else: 0.0)
            max == g -> (b - r) / d + 2.0
            true -> (r - g) / d + 4.0
          end

        {h / 6.0, s}
      end

    {h, s, l}
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

  defp lerp(a, b, t), do: a + (b - a) * t

  defp lerp_color({r1, g1, b1}, {r2, g2, b2}, t) do
    {lerp(r1, r2, t), lerp(g1, g2, t), lerp(b1, b2, t)}
  end

  defp scale({r, g, b}, f) do
    {clamp_byte(r * f), clamp_byte(g * f), clamp_byte(b * f)}
  end

  defp clamp(v, lo, hi), do: v |> max(lo) |> min(hi)

  defp clamp_byte(v), do: v |> trunc() |> max(0) |> min(255)

  defp clamp01(v), do: v |> max(0.0) |> min(1.0)
end
