defmodule Octopus.Apps.ShapeShifter do
  @moduledoc """
  Shape Shifter mask app – displays geometric shapes as a grayscale mask.

  Cycles through Circle, Square, Triangle, Star, and Heart, cross-fading between
  them smoothly. Each shape continuously rotates while a second "axis" rotation
  creates a 3D tumbling effect (like a coin flipping in perspective).

  The app renders the same shape on every 8×8 panel independently, so the mask
  looks uniform across the installation.
  """

  use Octopus.App, category: :animation, output_type: :grayscale

  alias Octopus.Canvas

  @fps 30
  @frame_time_ms trunc(1000 / @fps)

  @shapes [:circle, :square, :triangle, :star, :heart]
  @num_shapes length(@shapes)

  @panel_width 8
  # Radius within the 8×8 panel (centre at 3.5, 3.5; max distance to edge is 3.5)
  @panel_radius 3.0

  @default_shape_duration 5.0
  @default_transition_duration 1.5
  @default_rotation_speed 60.0
  @default_axis_speed 45.0
  @default_edge_softness 0.5

  def name, do: "Shape Shifter"

  def app_init(config) do
    Octopus.App.configure_display(
      layout: :adjacent_panels,
      supports_rgb: false,
      supports_grayscale: true,
      easing_interval: 0
    )

    display_info = Octopus.App.get_display_info()
    :timer.send_after(@frame_time_ms, :tick)

    {:ok,
     %{
       display_info: display_info,
       t: 0.0,
       rotation: 0.0,
       axis_angle: 0.0,
       shape_duration: Map.get(config, :shape_duration, @default_shape_duration),
       transition_duration: Map.get(config, :transition_duration, @default_transition_duration),
       rotation_speed: Map.get(config, :rotation_speed, @default_rotation_speed),
       axis_speed: Map.get(config, :axis_speed, @default_axis_speed),
       edge_softness: Map.get(config, :edge_softness, @default_edge_softness)
     }}
  end

  def handle_info(:tick, state) do
    :timer.send_after(@frame_time_ms, :tick)

    dt = @frame_time_ms / 1000.0
    t = state.t + dt
    rotation = state.rotation + state.rotation_speed * dt
    axis_angle = state.axis_angle + state.axis_speed * dt

    period = state.shape_duration
    t_in_cycle = glsl_mod(t, period * @num_shapes)
    shape_index = trunc(t_in_cycle / period)
    t_in_shape = t_in_cycle - shape_index * period

    transition_start = max(period - state.transition_duration, 0.0)

    blend =
      if t_in_shape >= transition_start and state.transition_duration > 0.0 do
        min((t_in_shape - transition_start) / state.transition_duration, 1.0)
      else
        0.0
      end

    current_shape = Enum.at(@shapes, rem(shape_index, @num_shapes))
    next_shape = Enum.at(@shapes, rem(shape_index + 1, @num_shapes))

    canvas =
      render_canvas(
        state.display_info,
        rotation,
        axis_angle,
        current_shape,
        next_shape,
        blend,
        state.edge_softness
      )

    Octopus.App.update_display(canvas, :grayscale)

    {:noreply, %{state | t: t, rotation: rotation, axis_angle: axis_angle}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp render_canvas(display_info, rotation, axis_angle, current_shape, next_shape, blend, edge_softness) do
    rot_rad = rotation * :math.pi() / 180.0
    axis_rad = axis_angle * :math.pi() / 180.0
    cos_r = :math.cos(rot_rad)
    sin_r = :math.sin(rot_rad)
    cos_a = :math.cos(axis_rad)

    # Soft edge width: minimum 0.3 px; grows with the softness setting
    soft = edge_softness * @panel_radius * 0.4 + 0.3

    h = display_info.height
    w = display_info.width
    cy_center = (h - 1) / 2.0
    cx_half = (@panel_width - 1) / 2.0

    for y <- 0..(h - 1),
        x <- 0..(w - 1),
        reduce: Canvas.new(w, h, :grayscale) do
      acc ->
        # Panel-local coordinates, centred on each 8×8 panel
        panel_x = rem(x, @panel_width)
        cx = panel_x - cx_half
        cy = y - cy_center

        # Primary 2-D rotation of the shape
        rx = cx * cos_r - cy * sin_r
        ry = cx * sin_r + cy * cos_r

        # Axis squish: simulates a 3-D tumble by squeezing the rotated X axis,
        # like a coin spinning on a table viewed at an angle.
        ax = rx * cos_a
        ay = ry

        i1 = sdf_to_intensity(shape_sdf(current_shape, ax, ay, @panel_radius), soft)
        i2 = sdf_to_intensity(shape_sdf(next_shape, ax, ay, @panel_radius), soft)
        intensity = i1 * (1.0 - blend) + i2 * blend

        Canvas.put_pixel(acc, {x, y}, trunc(intensity * 255))
    end
  end

  # Maps a signed distance value to an intensity in [0.0, 1.0].
  # d < 0 → fully inside (1.0); d > 0 → fully outside (0.0); ±soft = transition zone.
  defp sdf_to_intensity(d, soft) when soft > 0.0 do
    clamp((soft - d) / (2.0 * soft), 0.0, 1.0)
  end

  defp sdf_to_intensity(d, _soft), do: if(d <= 0.0, do: 1.0, else: 0.0)

  # ---------------------------------------------------------------------------
  # Signed Distance Functions  (negative = inside shape, positive = outside)
  # ---------------------------------------------------------------------------

  # Circle
  defp shape_sdf(:circle, x, y, r) do
    :math.sqrt(x * x + y * y) - r
  end

  # Axis-aligned square
  defp shape_sdf(:square, x, y, r) do
    max(abs(x), abs(y)) - r
  end

  # Equilateral triangle (IQ formula)
  defp shape_sdf(:triangle, x, y, r) do
    k = :math.sqrt(3.0)
    px = abs(x) - r
    py = y + r / k

    {px2, py2} =
      if px + k * py > 0.0 do
        {(px - k * py) / 2.0, (-k * px - py) / 2.0}
      else
        {px, py}
      end

    px3 = px2 - clamp(px2, -2.0 * r, 0.0)
    -:math.sqrt(px3 * px3 + py2 * py2) * float_sign(py2)
  end

  # 5-pointed star (IQ formula, n=5, m=2.5 for classic star proportions).
  # The formula's `r` parameter sets the polygon circumradius; the actual star
  # tips land at roughly r*cos(π/5) ≈ 0.81 r.  We scale r up to compensate.
  defp shape_sdf(:star, x, y, r) do
    r_param = r / 0.81

    an = :math.pi() / 5
    en = :math.pi() / 2.5
    acs_x = :math.cos(an)
    acs_y = :math.sin(an)
    ecs_x = :math.cos(en)
    ecs_y = :math.sin(en)

    angle = :math.atan2(y, x)
    bn = glsl_mod(angle, 2.0 * an) - an
    len = :math.sqrt(x * x + y * y)
    px = len * :math.cos(bn)
    py = len * abs(:math.sin(bn))

    px2 = px - r_param * acs_x
    py2 = py - r_param * acs_y
    dot_neg = -(px2 * ecs_x + py2 * ecs_y)
    clamped = clamp(dot_neg, 0.0, r_param * acs_y / ecs_y)

    px3 = px2 + ecs_x * clamped
    py3 = py2 + ecs_y * clamped

    :math.sqrt(px3 * px3 + py3 * py3) * float_sign(px3)
  end

  # Heart (IQ formula scaled so the heart fills the panel radius).
  # In IQ unit space the heart spans roughly x ∈ [0, 0.75] and y ∈ [0, 1.25].
  # We scale so the widest point (≈ 0.6 units) lands at r pixels.
  defp shape_sdf(:heart, x, y, r) do
    scale = r / 0.6
    nx = abs(x / scale)
    # Flip y (so the bump is at the top on-screen) and centre the heart vertically.
    ny = -y / scale + 0.6

    d =
      if ny + nx > 1.0 do
        vx = nx - 0.25
        vy = ny - 0.75
        :math.sqrt(vx * vx + vy * vy) - :math.sqrt(2.0) / 4.0
      else
        vx1 = nx
        vy1 = ny - 1.0
        vx2 = nx - 0.5
        vy2 = ny - 0.5
        d1 = :math.sqrt(vx1 * vx1 + vy1 * vy1) - 0.5
        d2 = :math.sqrt(vx2 * vx2 + vy2 * vy2) - 0.5
        min(d1, d2)
      end

    d * scale
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  # GLSL-compatible modulo: always returns a non-negative result for positive y.
  defp glsl_mod(x, y), do: x - y * :math.floor(x / y)

  defp clamp(v, lo, hi), do: v |> max(lo) |> min(hi)

  defp float_sign(x) when x > 0.0, do: 1.0
  defp float_sign(x) when x < 0.0, do: -1.0
  defp float_sign(_), do: 0.0

  # ---------------------------------------------------------------------------
  # Config / UI
  # ---------------------------------------------------------------------------

  def config_schema do
    %{
      shape_duration:
        {"Shape duration", :float,
         %{min: 1.0, max: 30.0, step: 0.5, unit: "s", default: @default_shape_duration}},
      transition_duration:
        {"Transition duration", :float,
         %{min: 0.1, max: 10.0, step: 0.1, unit: "s", default: @default_transition_duration}},
      rotation_speed:
        {"Rotation speed", :float,
         %{min: 0.0, max: 360.0, step: 5.0, unit: "°/s", default: @default_rotation_speed}},
      axis_speed:
        {"Axis speed", :float,
         %{min: 0.0, max: 180.0, step: 5.0, unit: "°/s", default: @default_axis_speed}},
      edge_softness:
        {"Edge softness", :float,
         %{min: 0.0, max: 1.0, step: 0.05, default: @default_edge_softness}}
    }
  end

  def get_config(state) do
    %{
      shape_duration: state.shape_duration,
      transition_duration: state.transition_duration,
      rotation_speed: state.rotation_speed,
      axis_speed: state.axis_speed,
      edge_softness: state.edge_softness
    }
  end

  def handle_config(config, state) do
    {:noreply,
     %{
       state
       | shape_duration: Map.get(config, :shape_duration, state.shape_duration),
         transition_duration: Map.get(config, :transition_duration, state.transition_duration),
         rotation_speed: Map.get(config, :rotation_speed, state.rotation_speed),
         axis_speed: Map.get(config, :axis_speed, state.axis_speed),
         edge_softness: Map.get(config, :edge_softness, state.edge_softness)
     }}
  end

  def now_playing_meta(config) do
    shape_dur = Map.get(config, :shape_duration, @default_shape_duration)
    rot = Map.get(config, :rotation_speed, @default_rotation_speed)
    [
      "shape #{shape_dur}s",
      "rot #{trunc(rot)}°/s"
    ]
  end
end
