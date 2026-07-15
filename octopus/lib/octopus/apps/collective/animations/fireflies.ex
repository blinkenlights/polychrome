defmodule Octopus.Apps.Collective.Animations.Fireflies do
  @moduledoc """
  Fireflies — soft bioluminescent points drifting over a night field, driven by
  crowd activity.

  Each firefly drifts slowly over a dark field with a soft, breathing glow — no
  discrete blinks. Rendering is additive with a Gaussian falloff, so overlapping
  fireflies bloom together into a brighter, warmer core when they cluster.

  Crowd input comes from `Octopus.Radar.PanelActivity` via `Radar.panel_factors/0`:

    * global heat → more fireflies spawn (they fade in, so there is no popping),
    * local heat  → fireflies are attracted toward hot panels and cluster into a
      swarm over the busiest part of the ring.

  `Firefly Activity` (`:firefly_reactivity`) is the master gain; at 0 the animation
  is a calm, crowd-blind meadow of a fixed number of fireflies (safe fallback with
  no sensor).

  Authored for a 12-panel (96 px wide) × 8 px ring; `layout_scale/1` keeps glow
  radii sensible on smaller rings too.
  """

  @behaviour Octopus.Apps.Collective.Animation

  alias Octopus.Canvas
  alias Octopus.Radar
  alias Octopus.Radar.PanelMapping

  @two_pi 2.0 * :math.pi()
  @panel_width 8

  # Ring layout the parameters were authored for (12 panels × 8 px).
  @reference_circumference 96
  # Below this width, linear scale alone makes glows vanish; floor keeps small
  # rings readable (mirrors the Lava Lamp).
  @small_ring_width 16
  @small_ring_min_scale 0.28

  # Fixed pool of fireflies. `presence` (0..1) gates how many are actually visible,
  # so spawning/despawning with the crowd is a smooth fade instead of list churn.
  @pool_size 40
  @default_base_count 24
  # How fast presence fades in / out (units of presence per second).
  @presence_rate 0.9

  # --- motion / clustering --------------------------------------------------
  # Gentle wander + slow pull toward hotter panels.
  @wander_th 0.06
  @wander_y 0.22
  @damping 1.6
  @center_pull 0.45
  @attract_gain 1.8
  @v_th_max 0.45
  @v_y_max 1.4

  # --- glow / breath --------------------------------------------------------
  @breath_base 0.22
  @breath_amp 0.30
  # Soft halo — smaller than the original flashy build, but wide enough to read on 8 px.
  @glow_sigma 1.08
  # Light-units → 8-bit gain.
  @light_scale 255.0

  # Palettes as {dim_glow, warm_peak}, channels normalised 0..1.
  @palettes %{
    classic: {{0.62, 0.72, 0.10}, {1.00, 0.90, 0.38}},
    amber: {{0.88, 0.68, 0.14}, {1.00, 0.82, 0.32}},
    ghost: {{0.32, 0.82, 0.68}, {0.86, 1.00, 0.98}}
  }

  # Deep-dusk background gradient (top → bottom), kept near black so the fireflies
  # carry the image.
  @bg_top {2, 5, 12}
  @bg_bottom {1, 3, 6}

  @impl true
  def name, do: "Fireflies"

  @impl true
  def init(%{width: width}) do
    scale = layout_scale(width)

    %{
      t: 0.0,
      base_count: @default_base_count,
      layout_scale: scale,
      # Wake the baseline meadow immediately; crowd spawns still ease in/out.
      fireflies:
        generate_fireflies(@pool_size, scale)
        |> Enum.with_index()
        |> Enum.map(fn {fly, idx} ->
          if idx < @default_base_count, do: %{fly | presence: 1.0}, else: fly
        end)
    }
  end

  @impl true
  def render(%Canvas{} = canvas, _people, ctx, state) do
    # Guard against a huge step after a stall (keeps the sim stable).
    dt = ctx.dt |> clamp(0.0, 0.2)
    speed = Map.get(ctx, :firefly_speed, 1.5) |> clamp(0.2, 3.0)
    base_count = Map.get(ctx, :firefly_count, @default_base_count) |> clamp_int(1, @pool_size)
    reactivity = Map.get(ctx, :firefly_reactivity, 0.6) |> clamp(0.0, 1.0)
    glow_mul = Map.get(ctx, :firefly_glow, 1.0) |> clamp(0.5, 1.8)
    breath_depth = Map.get(ctx, :firefly_flash_rate, 0.85) |> clamp(0.4, 1.2)
    {dim_n, hot_n} = palette(Map.get(ctx, :firefly_palette, :classic))

    width = canvas.width
    height = canvas.height
    circumference = max(width, 1)
    layout_scale = layout_scale(circumference)
    num_panels = max(div(width, @panel_width), 1)

    heat = frame_heat(num_panels)
    heat_global = (heat |> Map.values() |> Enum.sum()) / num_panels

    # Crowd spawns extra fireflies on top of the baseline count.
    target_count =
      (base_count + reactivity * heat_global * (@pool_size - base_count))
      |> round()
      |> clamp_int(1, @pool_size)

    # Advance a speed-scaled clock; motion and breath integrate against `dts`.
    dts = dt * speed
    t = state.t + dts

    fireflies =
      state.fireflies
      |> Enum.with_index()
      |> Enum.map(fn {fly, idx} ->
        update_firefly(fly, idx, dts, t, height, heat, num_panels, reactivity, breath_depth,
          target_count)
      end)

    posed =
      for fly <- fireflies, fly.presence > 0.01 do
        pose_firefly(fly, layout_scale, glow_mul, dim_n, hot_n)
      end

    k = circumference / @two_pi

    pixels =
      for x <- 0..(width - 1), y <- 0..(height - 1), into: %{} do
        theta_px = x / circumference * @two_pi
        {ar, ag, ab} = accumulate_light(theta_px, y, posed, k)
        {{x, y}, blend_bg(y, height, ar, ag, ab)}
      end

    new_state = %{
      state
      | t: t,
        base_count: base_count,
        layout_scale: layout_scale,
        fireflies: fireflies
    }

    {%Canvas{canvas | pixels: pixels}, new_state}
  end

  # --- per-firefly update ---------------------------------------------------

  defp update_firefly(fly, idx, dts, t, height, heat, num_panels, reactivity, breath_depth,
         target_count) do
    presence = ease_presence(fly.presence, idx < target_count, dts)

    breath =
      @breath_base +
        @breath_amp * breath_depth *
          (0.5 + 0.5 * :math.sin(@two_pi * t / fly.breath_period + fly.breath_phase))

    grad = heat_gradient(fly.theta, heat, num_panels)
    y_center = (height - 1) / 2.0

    th_dir = Map.get(fly, :th_dir, 1.0)
    y_dir = Map.get(fly, :y_dir, 1.0)

    a_th =
      th_dir *
        (@wander_th * wander_th(t, fly) + reactivity * @attract_gain * grad) - @damping * fly.vth

    a_y =
      y_dir * (@wander_y * wander_y(t, fly) + @center_pull * (y_center - fly.y)) - @damping * fly.vy

    vth = clamp(fly.vth + a_th * dts, -@v_th_max, @v_th_max)
    vy = clamp(fly.vy + a_y * dts, -@v_y_max, @v_y_max)

    theta = norm_theta(fly.theta + vth * dts)
    {y, vy} = drift_y(fly.y + vy * dts, vy, height)

    %{
      fly
      | theta: theta,
        y: y,
        vth: vth,
        vy: vy,
        breath: breath,
        presence: presence
    }
  end

  defp wander_th(t, fly) do
    period2 = Map.get(fly, :wth_period2, fly.wth_period * 0.55)
    phase2 = Map.get(fly, :wth_phase2, 0.0)

    :math.sin(@two_pi * t / fly.wth_period + fly.wth_phase) +
      0.38 * :math.sin(@two_pi * t / period2 + phase2)
  end

  defp wander_y(t, fly) do
    period2 = Map.get(fly, :wy_period2, fly.wy_period * 0.58)
    phase2 = Map.get(fly, :wy_phase2, 0.0)

    :math.sin(@two_pi * t / fly.wy_period + fly.wy_phase) +
      0.32 * :math.sin(@two_pi * t / period2 + phase2)
  end

  defp ease_presence(presence, active?, dts) do
    step = @presence_rate * dts
    target = if active?, do: 1.0, else: 0.0

    cond do
      target > presence -> min(target, presence + step)
      target < presence -> max(target, presence - step)
      true -> presence
    end
  end

  # Soft reflection at top/bottom so fireflies float within the strip.
  defp drift_y(y, vy, height) do
    lo = 0.5
    hi = height - 1 - 0.5
    hi = max(hi, lo)

    cond do
      y < lo -> {lo, abs(vy) * 0.5}
      y > hi -> {hi, -abs(vy) * 0.5}
      true -> {y, vy}
    end
  end

  defp pose_firefly(fly, layout_scale, glow_mul, dim_n, hot_n) do
    emit = fly.presence * fly.breath
    breath_t = clamp((fly.breath - @breath_base) / max(@breath_amp, 0.001), 0.0, 1.0)
    warm = breath_t * 0.45
    color_n = lerp3(dim_n, hot_n, warm)
    sigma = @glow_sigma * layout_scale * glow_mul

    {fly.theta, fly.y, emit, sigma, color_n}
  end

  # --- rendering ------------------------------------------------------------

  defp accumulate_light(theta_px, y, posed, k) do
    Enum.reduce(posed, {0.0, 0.0, 0.0}, fn {th, yb, emit, sigma, {cr, cg, cb}},
                                           {ar, ag, ab} ->
      dth = angular_dist(theta_px, th)
      dx = dth * k
      dy = y - yb
      g = :math.exp(-(dx * dx + dy * dy) / (2.0 * sigma * sigma))
      l = emit * g
      {ar + l * cr, ag + l * cg, ab + l * cb}
    end)
  end

  defp blend_bg(y, height, ar, ag, ab) do
    {tr, tg, tb} = @bg_top
    {br, bg, bb} = @bg_bottom
    f = y / max(height - 1, 1)

    r = round(lerp(tr, br, f) + ar * @light_scale) |> clamp8()
    g = round(lerp(tg, bg, f) + ag * @light_scale) |> clamp8()
    b = round(lerp(tb, bb, f) + ab * @light_scale) |> clamp8()
    {r, g, b}
  end

  # --- crowd heat (identical model to the Lava Lamp) ------------------------

  defp frame_heat(num_panels) do
    factors = Radar.panel_factors()
    north = Radar.north_panel()

    for frame_panel <- 0..(num_panels - 1), into: %{} do
      install = PanelMapping.installation_panel_of_frame(frame_panel, num_panels, north)
      {frame_panel, Map.get(factors, install, 0.0)}
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

  # --- generation & helpers -------------------------------------------------

  @doc false
  def generate_fireflies(count, _layout_scale \\ 1.0) do
    for _i <- 0..(count - 1) do
      wth_period = 9.0 + rand_uniform(0.0, 19.0)
      wy_period = 6.5 + rand_uniform(0.0, 13.0)

      %{
        theta: rand_uniform(0.0, @two_pi),
        y: rand_uniform(1.5, 6.5),
        vth: rand_uniform(-0.12, 0.12),
        vy: rand_uniform(-0.18, 0.18),
        th_dir: if(:rand.uniform() > 0.5, do: 1.0, else: -1.0),
        y_dir: if(:rand.uniform() > 0.5, do: 1.0, else: -1.0),
        wth_period: wth_period,
        wth_period2: wth_period * rand_uniform(0.35, 0.72),
        wth_phase: rand_uniform(0.0, @two_pi),
        wth_phase2: rand_uniform(0.0, @two_pi),
        wy_period: wy_period,
        wy_period2: wy_period * rand_uniform(0.38, 0.78),
        wy_phase: rand_uniform(0.0, @two_pi),
        wy_phase2: rand_uniform(0.0, @two_pi),
        breath_period: 4.5 + rand_uniform(0.0, 7.5),
        breath_phase: rand_uniform(0.0, @two_pi),
        breath: @breath_base,
        presence: 0.0
      }
    end
  end

  defp palette(p) when is_atom(p), do: Map.get(@palettes, p, @palettes.classic)

  defp layout_scale(circumference) when is_number(circumference) do
    linear = circumference / @reference_circumference

    if circumference <= @small_ring_width do
      max(linear, @small_ring_min_scale)
    else
      linear
    end
  end

  defp angular_dist(a, b) do
    d = abs(a - b) |> :math.fmod(@two_pi)
    if d > :math.pi(), do: @two_pi - d, else: d
  end

  defp norm_theta(theta) do
    m = :math.fmod(theta, @two_pi)
    if m < 0.0, do: m + @two_pi, else: m
  end

  defp lerp3({r1, g1, b1}, {r2, g2, b2}, t) do
    {lerp(r1, r2, t), lerp(g1, g2, t), lerp(b1, b2, t)}
  end

  defp rand_uniform(a, b), do: a + :rand.uniform() * (b - a)

  defp lerp(a, b, t), do: a + (b - a) * t
  defp clamp(v, lo, hi), do: v |> max(lo) |> min(hi)
  defp clamp_int(v, lo, hi), do: v |> trunc() |> max(lo) |> min(hi)
  defp clamp8(v), do: v |> max(0) |> min(255)
end
