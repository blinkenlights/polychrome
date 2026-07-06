defmodule Octopus.Apps.Collective.Animations.Dots do
  @moduledoc """
  Crowd Dots — one pixel per person on the ring strip.

  * X — angular position on the circle (same mapping as Rain / Tempest)
  * Y — distance from centre: at the ring (near the panels) → bottom row;
    at the centre → top row
  """

  @behaviour Octopus.Apps.Collective.Animation

  alias Octopus.Canvas
  alias Octopus.Radar.PanelMapping

  @panel_width 8
  @bg {0, 0, 0}

  @impl true
  def name, do: "Crowd Dots"

  @impl true
  def init(_display_info), do: %{positions: %{}}

  @impl true
  def render(canvas, people, ctx, state) do
    dt = ctx.dt
    width = canvas.width
    height = canvas.height
    num_panels = max(div(width, @panel_width), 1)
    ring_outer = PanelMapping.ring_radius()

    smooth = Map.get(ctx, :dots_smoothing, 0.35) |> clamp01()
    tau = lerp(0.04, 0.22, smooth)
    alpha = 1.0 - :math.exp(-dt / tau)

    active_ids = MapSet.new(people, & &1.id)

    positions =
      Enum.reduce(people, state.positions, fn person, acc ->
        target = person_canvas_xy(person, num_panels, height, ring_outer)
        {sx, sy} = Map.get(acc, person.id, target)
        sx = sx + (elem(target, 0) - sx) * alpha
        sy = sy + (elem(target, 1) - sy) * alpha
        Map.put(acc, person.id, {sx, sy})
      end)
      |> Map.take(MapSet.to_list(active_ids))

    canvas =
      canvas
      |> Canvas.fill(@bg)
      |> draw_people(people, positions, width, height)

    {canvas, %{state | positions: positions}}
  end

  defp draw_people(canvas, people, positions, width, height) do
    Enum.reduce(people, canvas, fn person, c ->
      {sx, sy} = Map.fetch!(positions, person.id)
      x = trunc(sx) |> clamp(0, width - 1)
      y = trunc(sy) |> clamp(0, height - 1)
      color = id_color(person.id)
      Canvas.put_pixel(c, {x, y}, color)
    end)
  end

  defp person_canvas_xy(person, num_panels, height, ring_outer) do
    col = person_column_f(person, num_panels)
    row = radius_to_y(PanelMapping.track_radius(person), height, ring_outer)
    {col, row}
  end

  # Canvas column with frame-panel flip (matches aframe textureIdx = N - i - 1).
  defp person_column_f(person, num_panels) do
    norm = PanelMapping.angle_norm(person)
    total = norm * num_panels * @panel_width
    sim_panel = min(trunc(total / @panel_width), num_panels - 1)
    within = total - sim_panel * @panel_width
    frame_panel = PanelMapping.frame_panel_of_3d(sim_panel, num_panels)
    frame_panel * @panel_width + within
  end

  # Centre (r → 0) = top (y 0); ring edge (r → ring_outer) = bottom.
  defp radius_to_y(r, height, ring_outer) do
    t = (r / ring_outer) |> clamp01()
    t * (height - 1)
  end

  defp id_color(id) do
    hue = rem(id * 137, 360) / 360.0
    hsl_to_rgb(hue, 0.9, 0.62)
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
  defp clamp(v, lo, hi), do: v |> max(lo) |> min(hi)
  defp clamp_byte(v), do: v |> trunc() |> max(0) |> min(255)
  defp clamp01(v), do: v |> max(0.0) |> min(1.0)
end
