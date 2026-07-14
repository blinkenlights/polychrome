defmodule Octopus.Apps.Collective.Animations.LavaLamp do
  @moduledoc """
  Lava Lamp — cylindrical metaball blobs on the LED ring, driven by crowd heat.

  Slow sinusoidal rise/fall, soft sigmoid colouring, seamless wrap at panel 12→1.

  Crowd input is modelled as **heat** via the shared `CrowdActivity` factor
  (radius weight × walk multiplier, auto-gained, then per-panel EMA-smoothed):

    * global heat → convection speed + turbulence and palette temperature.
    * local heat  → per-blob buoyancy (rises over active panels), radius boost,
      and angular attraction toward hot panels.
    * people-as-blobs → each present person optionally spawns a transient blob at
      their angular position that grows while present and decays when they leave.

  `Crowd Heat` (`:lava_reactivity`) is the master gain; at 0 the animation is the
  original crowd-blind decorative lava (safe fallback with no sensor).

  Blob sizes are tuned for a 12-panel (96 px wide) ring and scaled down for
  smaller installations (e.g. Pixie 8×8) so the field does not saturate every pixel.
  """

  @behaviour Octopus.Apps.Collective.Animation

  alias Octopus.Apps.Collective.CrowdActivity
  alias Octopus.Canvas
  alias Octopus.Installation
  alias Octopus.Radar.PanelMapping

  @two_pi 2.0 * :math.pi()
  @field_softness 0.35
  @panel_width 8
  # Ring layout the blob parameters were authored for (12 panels × 8 px).
  @reference_circumference 96
  # Below this width, linear scale alone makes blobs invisible; floor keeps Pixie readable.
  @small_ring_width 16
  @small_ring_min_scale 0.28

  # Time constant (s) for the per-panel heat EMA (keeps crowd input from flickering).
  @heat_time_tau 0.6

  # How strongly local heat lifts a blob toward the top (fraction of strip height).
  @buoyancy_gain 0.6
  # How strongly local heat inflates a blob's radius.
  @radius_gain 0.5
  # Radians a blob drifts toward a hot panel per unit heat gradient.
  @attract_gain 0.6

  # Person-blob dynamics.
  @person_grow_tau 1.2
  @person_decay_tau 1.5
  @person_min_life 0.03
  @person_rise 0.5
  @person_base_r 1.6

  @palettes %{
    classic: [
      {12, 2, 8},
      {42, 6, 10},
      {112, 18, 8},
      {200, 52, 8},
      {248, 120, 20},
      {255, 208, 96},
      {255, 250, 214}
    ],
    magenta: [
      {6, 2, 16},
      {28, 6, 42},
      {92, 12, 86},
      {190, 32, 120},
      {240, 92, 150},
      {252, 180, 208},
      {255, 244, 250}
    ],
    slime: [
      {3, 10, 6},
      {10, 32, 14},
      {24, 78, 20},
      {62, 140, 26},
      {130, 200, 40},
      {204, 240, 90},
      {248, 255, 200}
    ]
  }

  # Cold end of the temperature axis: an empty room reads as a slow blue lamp.
  @cold_palette [
    {2, 4, 14},
    {6, 14, 40},
    {12, 40, 90},
    {24, 86, 150},
    {60, 150, 210},
    {150, 210, 240},
    {230, 248, 255}
  ]

  @impl true
  def name, do: "Lava Lamp"

  @impl true
  def init(%{width: width}) do
    scale = layout_scale(width)
    count = 7
    num_panels = max(div(width, @panel_width), 1)

    %{
      t: 0.0,
      blob_count: count,
      layout_scale: scale,
      blobs: generate_blobs(count, scale),
      ref: CrowdActivity.min_ref(),
      heat: for(p <- 0..(num_panels - 1), into: %{}, do: {p, 0.0}),
      person_blobs: %{}
    }
  end

  @impl true
  def render(%Canvas{} = canvas, people, ctx, state) do
    dt = ctx.dt
    speed = Map.get(ctx, :lava_speed, 1.0) |> clamp(0.2, 3.0)
    size_mul = Map.get(ctx, :lava_size_mul, 1.25) |> clamp(0.6, 2.2)
    base_thresh = Map.get(ctx, :lava_thresh, 0.9) |> clamp(0.4, 1.6)
    palette = palette_stops(Map.get(ctx, :lava_palette, :classic))
    blob_count = Map.get(ctx, :lava_blob_count, 7) |> clamp_int(3, 12)
    reactivity = Map.get(ctx, :lava_reactivity, 0.6) |> clamp(0.0, 1.0)
    warmth = Map.get(ctx, :lava_warmth, 0.5) |> clamp(0.0, 1.0)
    people_blobs? = Map.get(ctx, :lava_people_blobs, true)

    state = ensure_blobs(state, blob_count)

    width = canvas.width
    height = canvas.height
    circumference = max(width, 1)
    layout_scale = layout_scale(circumference)
    num_panels = max(div(width, @panel_width), 1)

    ring_outer = PanelMapping.ring_radius()
    raw = CrowdActivity.raw_factors(people, num_panels, ring_outer)
    ref = CrowdActivity.update_ref(state.ref, raw, true, dt)

    target_heat =
      for p <- 0..(num_panels - 1), into: %{} do
        {p, CrowdActivity.soft(Map.get(raw, p, 0.0) / ref)}
      end

    heat = smooth_heat(state.heat, target_heat, num_panels, dt)
    heat_global = (heat |> Map.values() |> Enum.sum()) / num_panels

    t = state.t + dt
    t_anim = t * speed * (1.0 + reactivity * heat_global)
    thresh = clamp(base_thresh * (1.0 - 0.35 * reactivity * heat_global), 0.3, 1.6)

    person_blobs =
      update_person_blobs(state.person_blobs, people, people_blobs?, ring_outer, dt)

    posed =
      pose_ambient_blobs(
        state.blobs,
        t_anim,
        circumference,
        height,
        size_mul,
        heat,
        num_panels,
        reactivity
      ) ++
        pose_person_blobs(person_blobs, height, layout_scale, size_mul)

    # Cool the palette toward blue when the room is empty; gated by reactivity so
    # Crowd Heat 0 keeps the full (hot) decorative palette.
    temp_cool = clamp(warmth * (1.0 - heat_global) * reactivity, 0.0, 1.0)
    stops = temperature_palette(palette, temp_cool)

    pixels =
      for x <- 0..(width - 1), y <- 0..(height - 1), into: %{} do
        theta_px = x / circumference * @two_pi
        field = field_at(theta_px, y, posed, circumference, height)
        color = pixel_color(field, y, height, thresh, stops)
        {{x, y}, color}
      end

    new_state = %{
      state
      | t: t,
        layout_scale: layout_scale,
        ref: ref,
        heat: heat,
        person_blobs: person_blobs
    }

    {%Canvas{canvas | pixels: pixels}, new_state}
  end

  @doc false
  def field_at(theta_px, y, posed_blobs, circumference, height \\ 8) do
    _ = height
    layout_scale = layout_scale(circumference)
    k = circumference / @two_pi
    softness = @field_softness * layout_scale * layout_scale

    Enum.reduce(posed_blobs, 0.0, fn {theta_blob, y_blob, radius}, acc ->
      dth = angular_dist(theta_px, theta_blob)
      dx = dth * k
      dy = (y - y_blob) * 1.15
      r2 = radius * radius
      acc + r2 / (dx * dx + dy * dy + softness)
    end)
  end

  @doc """
  Poses the ambient (crowd-blind) blobs into `{theta, y, radius}` tuples once per
  frame, folding in crowd heat (buoyancy, radius, attraction) when supplied.
  """
  def pose_ambient_blobs(
        blobs,
        t,
        circumference,
        height \\ 8,
        size_mul \\ 1.25,
        heat \\ %{},
        num_panels \\ 1,
        reactivity \\ 0.0
      ) do
    layout_scale = layout_scale(circumference)

    Enum.map(blobs, fn blob ->
      blob_pose(blob, t, size_mul, layout_scale, height, heat, num_panels, reactivity)
    end)
  end

  @doc false
  def encode_frame_data(%Canvas{} = canvas) do
    panel_width = Installation.panel_width()
    panel_height = Installation.panel_height()

    for panel_id <- 0..(Installation.num_panels() - 1),
        y <- 0..(panel_height - 1),
        x <- 0..(panel_width - 1) do
      canvas_x = panel_id * panel_width + x
      {r, g, b} = Canvas.get_pixel(canvas, {canvas_x, y})
      [r, g, b]
    end
    |> IO.iodata_to_binary()
  end

  @doc false
  def generate_blobs(count, _layout_scale \\ 1.0) do
    for i <- 0..(count - 1) do
      n = count

      %{
        theta0: i / n * @two_pi + rand_uniform(0, 0.8),
        drift: rand_uniform(-0.05, 0.05),
        r: 1.5 + rand_uniform(0, 1.4),
        y_period: 18 + rand_uniform(0, 26),
        y_phase: rand_uniform(0, @two_pi),
        y_amp: 2.6 + rand_uniform(0, 1.2),
        wob_period: 5 + rand_uniform(0, 7),
        wob_phase: rand_uniform(0, @two_pi),
        pulse_period: 9 + rand_uniform(0, 12),
        pulse_phase: rand_uniform(0, @two_pi)
      }
    end
  end

  defp layout_scale(circumference) when is_number(circumference) do
    linear = circumference / @reference_circumference

    if circumference <= @small_ring_width do
      max(linear, @small_ring_min_scale)
    else
      linear
    end
  end

  defp ensure_blobs(%{blob_count: existing} = state, existing), do: state

  defp ensure_blobs(%{layout_scale: scale} = state, count) do
    %{state | blob_count: count, blobs: generate_blobs(count, scale)}
  end

  defp blob_pose(blob, t, size_mul, layout_scale, height, heat, num_panels, reactivity) do
    y_center = (height - 1) / 2.0

    theta_base =
      blob.theta0 + blob.drift * t +
        0.12 * :math.sin(@two_pi * t / blob.wob_period + blob.wob_phase)

    heat_local = heat_at(theta_base, heat, num_panels)
    grad = heat_gradient(theta_base, heat, num_panels)

    theta_blob = theta_base + reactivity * @attract_gain * grad
    rise = reactivity * heat_local * (height - 1) * @buoyancy_gain

    y_blob =
      y_center - rise +
        blob.y_amp * layout_scale *
          :math.sin(@two_pi * t / blob.y_period + blob.y_phase)

    radius =
      blob.r * size_mul * layout_scale *
        (1 + 0.18 * :math.sin(@two_pi * t / blob.pulse_period + blob.pulse_phase)) *
        (1.0 + reactivity * heat_local * @radius_gain)

    {theta_blob, y_blob, radius}
  end

  # --- crowd heat ----------------------------------------------------------

  defp smooth_heat(prev, target, num_panels, dt) do
    alpha = 1.0 - :math.exp(-dt / @heat_time_tau)

    for p <- 0..(num_panels - 1), into: %{} do
      cur = Map.get(prev, p, 0.0)
      {p, cur + (Map.get(target, p, 0.0) - cur) * alpha}
    end
  end

  defp heat_at(_theta, heat, _num_panels) when map_size(heat) == 0, do: 0.0

  defp heat_at(theta, heat, num_panels) do
    pos = norm_theta(theta) / @two_pi * num_panels
    i = trunc(pos)
    frac = pos - i
    p0 = rem(i, num_panels)
    p1 = rem(p0 + 1, num_panels)
    lerp(Map.get(heat, p0, 0.0), Map.get(heat, p1, 0.0), frac)
  end

  defp heat_gradient(_theta, heat, _num_panels) when map_size(heat) == 0, do: 0.0

  defp heat_gradient(theta, heat, num_panels) do
    d = @two_pi / max(num_panels, 1)
    heat_at(theta + d, heat, num_panels) - heat_at(theta - d, heat, num_panels)
  end

  # --- person blobs --------------------------------------------------------

  defp update_person_blobs(_prev, _people, false, _ring_outer, _dt), do: %{}

  defp update_person_blobs(prev, people, true, ring_outer, dt) do
    grow = 1.0 - :math.exp(-dt / @person_grow_tau)
    decay = 1.0 - :math.exp(-dt / @person_decay_tau)

    present =
      Enum.reduce(people, %{}, fn person, acc ->
        theta = @two_pi * PanelMapping.angle_norm(person)
        r = PanelMapping.track_radius(person)
        w_radius = 1.0 + 2.0 * clamp01(r / ring_outer)
        target = w_radius / 3.0

        {life0, theta0} =
          case Map.get(prev, person.id) do
            nil -> {0.0, theta}
            b -> {b.life, b.theta}
          end

        life = life0 + (target - life0) * grow
        theta_s = norm_theta(theta0 + ang_delta(theta0, theta) * grow)
        Map.put(acc, person.id, %{theta: theta_s, life: life})
      end)

    absent =
      prev
      |> Map.drop(Map.keys(present))
      |> Enum.reduce(%{}, fn {id, b}, acc ->
        life = b.life * (1.0 - decay)
        if life > @person_min_life, do: Map.put(acc, id, %{b | life: life}), else: acc
      end)

    Map.merge(present, absent)
  end

  defp pose_person_blobs(person_blobs, height, layout_scale, size_mul) do
    y_center = (height - 1) / 2.0

    for {_id, b} <- person_blobs do
      rise = b.life * (height - 1) * @person_rise
      y = y_center - rise
      radius = @person_base_r * size_mul * layout_scale * (0.4 + b.life)
      {b.theta, y, radius}
    end
  end

  # --- colour / temperature ------------------------------------------------

  defp temperature_palette(hot_stops, cool_amount) do
    hot_mix = clamp(1.0 - cool_amount, 0.0, 1.0)

    if hot_mix >= 0.999 do
      hot_stops
    else
      @cold_palette
      |> Enum.zip(hot_stops)
      |> Enum.map(fn {{cr, cg, cb}, {hr, hg, hb}} ->
        {round(lerp(cr, hr, hot_mix)), round(lerp(cg, hg, hot_mix)), round(lerp(cb, hb, hot_mix))}
      end)
    end
  end

  defp angular_dist(a, b) do
    d = abs(a - b) |> :math.fmod(@two_pi)
    if d > :math.pi(), do: @two_pi - d, else: d
  end

  defp pixel_color(field, y, height, thresh, palette) do
    y_norm = y / max(height - 1, 1)
    base = 0.06 + 0.05 * (1.0 - y_norm)
    x_sig = (field - thresh) / (thresh * 0.9) * 4.5
    s = sigmoid(x_sig)
    v = base + s * (0.97 - base)
    palette_color(palette, v)
  end

  defp sigmoid(x) do
    1.0 / (1.0 + :math.exp(-x))
  end

  defp palette_stops(palette) when is_atom(palette) do
    Map.fetch!(@palettes, palette)
  end

  defp palette_color(stops, v) do
    n = length(stops)
    x = v |> max(0.0) |> min(0.9999) |> Kernel.*(n - 1)
    i = trunc(x)
    t = x - i
    {r1, g1, b1} = Enum.at(stops, i)
    {r2, g2, b2} = Enum.at(stops, min(i + 1, n - 1))

    {round(lerp(r1, r2, t)), round(lerp(g1, g2, t)), round(lerp(b1, b2, t))}
  end

  defp norm_theta(theta) do
    m = :math.fmod(theta, @two_pi)
    if m < 0.0, do: m + @two_pi, else: m
  end

  defp ang_delta(from, to) do
    d = :math.fmod(to - from + :math.pi(), @two_pi)
    d = if d < 0.0, do: d + @two_pi, else: d
    d - :math.pi()
  end

  defp rand_uniform(a, b), do: a + :rand.uniform() * (b - a)

  defp lerp(a, b, t), do: a + (b - a) * t
  defp clamp(v, lo, hi), do: v |> max(lo) |> min(hi)
  defp clamp01(v), do: v |> max(0.0) |> min(1.0)
  defp clamp_int(v, lo, hi), do: v |> trunc() |> max(lo) |> min(hi)
end
