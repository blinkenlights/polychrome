defmodule Octopus.Apps.Collective.Animations.Storm do
  @moduledoc """
  Bewegungs-Sturm — the crowd's movement triggers lightning on the ring.

  Each person maps to a column on the ring (their angular position). The faster a
  person moves, the more likely a lightning bolt strikes at their position. Bolts
  are jagged vertical strokes that fade out over a short lifetime, so the effect
  reads as lightning without the single-frame strobing/flicker.

  The background is selectable via `ctx.background`:

    * `:deep_dark` — pure black sky (default).
    * `:still_stars` — a subtle, non-flickering night sky with static stars.

  `sensitivity` scales how readily movement spawns bolts.
  """

  @behaviour Octopus.Apps.Collective.Animation

  alias Octopus.Canvas

  # Per-person speed (m/s) that maps to the full bolt spawn rate.
  @ref_speed 1.0

  # Bolts per second a person triggers at full speed (before sensitivity).
  @max_bolt_rate 4.0

  # People within this radius (m) of the ring center trigger no lightning. Near
  # the center the angular position is ill-defined (atan2 is unstable), and there
  # is no meaningful panel to strike, so a central dead-zone avoids bolts spraying
  # across panels when someone crosses the middle.
  @center_dead_zone 3.0

  # Lightning lifetime (s) — how long a bolt fades out over.
  @bolt_ttl 0.2

  @bolt_core {210, 225, 255}
  @bolt_glow {60, 80, 150}

  # "Still Stars" background: a faint night-sky tint plus static stars.
  @sky_color {6, 10, 26}

  @impl true
  def name, do: "Tempest"

  @impl true
  def init(display_info) do
    %{bolts: [], stars: build_stars(display_info.width, display_info.height)}
  end

  @impl true
  def render(canvas, people, ctx, state) do
    dt = ctx.dt
    width = canvas.width
    height = canvas.height

    new_bolts = spawn_bolts(people, ctx.sensitivity, dt, width, height)

    bolts =
      (state.bolts ++ new_bolts)
      |> Enum.map(fn b -> %{b | age: b.age + dt} end)
      |> Enum.reject(fn b -> b.age >= @bolt_ttl end)

    canvas =
      canvas
      |> paint_background(Map.get(ctx, :background, :deep_dark), state.stars)
      |> draw_bolts(bolts)

    {canvas, %{state | bolts: bolts}}
  end

  # --- background ----------------------------------------------------------

  # Deep dark: leave the (already cleared) canvas black.
  defp paint_background(canvas, :deep_dark, _stars), do: canvas

  defp paint_background(canvas, :still_stars, stars) do
    canvas = Canvas.fill(canvas, @sky_color)
    Enum.reduce(stars, canvas, fn s, c -> Canvas.put_pixel(c, {s.x, s.y}, s.color) end)
  end

  # Fixed positions and brightness → no twinkle, no flicker.
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

  # --- spawning ------------------------------------------------------------

  defp spawn_bolts(people, sensitivity, dt, width, height) do
    Enum.flat_map(people, fn p ->
      radius = :math.sqrt(p.x * p.x + p.y * p.y)
      speed = :math.sqrt(p.vx * p.vx + p.vy * p.vy)

      cond do
        radius < @center_dead_zone ->
          []

        :rand.uniform() < spawn_prob(speed, sensitivity, dt) ->
          [build_bolt(person_column(p, width), height)]

        true ->
          []
      end
    end)
  end

  defp spawn_prob(speed, sensitivity, dt) do
    (speed / @ref_speed) |> clamp01() |> Kernel.*(@max_bolt_rate * sensitivity * dt)
  end

  @panel_width 8

  # Maps a person's angular position around the ring to a canvas column, matching
  # what the 3D sim actually shows.
  #
  #   * Person is rendered at world (X = x, Z = y).
  #   * Panel `i` sits at (X = sin θ, Z = cos θ), θ = i/num_panels · 2π, so the
  #     panel a person faces is atan2(X, Z) = atan2(x, y).
  #   * BUT the sim flips panel order when uploading frames
  #     (`textureIdx = numPanels - i - 1` in pixels3daframe.ts): frame panel `i`
  #     is displayed on sim panel `num_panels - 1 - i`.
  #
  # So we compute the sim panel the person faces, then reverse the panel index to
  # find the frame/canvas panel that lights it (keeping the within-panel offset).
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

  defp build_bolt(start_x, height) do
    {points, _} =
      Enum.map_reduce(0..(height - 1), start_x, fn y, x ->
        nx = x + (:rand.uniform(3) - 2)
        {{nx, y}, nx}
      end)

    %{points: points, age: 0.0}
  end

  # --- drawing -------------------------------------------------------------

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

  defp blend_pixel(%Canvas{width: w, height: h} = canvas, {x, y}, color)
       when x >= 0 and y >= 0 and x < w and y < h do
    existing = Canvas.get_pixel(canvas, {x, y})
    Canvas.put_pixel(canvas, {x, y}, add(existing, color))
  end

  defp blend_pixel(canvas, _coord, _color), do: canvas

  # --- helpers -------------------------------------------------------------

  defp add({r1, g1, b1}, {r2, g2, b2}) do
    {min(r1 + r2, 255), min(g1 + g2, 255), min(b1 + b2, 255)}
  end

  defp scale({r, g, b}, f), do: {trunc(r * f), trunc(g * f), trunc(b * f)}

  defp clamp(value, lo, hi), do: value |> max(lo) |> min(hi)

  defp clamp01(value), do: value |> max(0.0) |> min(1.0)
end
