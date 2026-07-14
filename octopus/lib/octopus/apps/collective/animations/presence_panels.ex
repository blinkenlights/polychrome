defmodule Octopus.Apps.Collective.Animations.PresencePanels do
  @moduledoc """
  Presence — each panel glows fully in a fixed random colour; brightness follows
  a per-panel crowd activity factor.

  Activity factor per panel = Σ over people mapped to that panel of
  `radius_weight * walk_multiplier`:

    * radius weight — near the mast (centre) counts 1, near the panels (ring
      outer) counts up to 3 (linear in `r / ring_radius`).
    * walk multiplier — moving faster than a small threshold counts double.

  The factor is normalised with a slow auto-gain (tracks the running panel max),
  soft-compressed, then smoothed in time (per panel) and space (bleeds into the
  two neighbours) so the result reads as soft crowd presence, not flicker.
  """

  @behaviour Octopus.Apps.Collective.Animation

  alias Octopus.Apps.Collective.CrowdActivity
  alias Octopus.Canvas
  alias Octopus.Radar.PanelMapping

  @panel_width 8

  # Fixed HSL for the random panel colours — only hue is random.
  @color_sat 0.85
  @color_light 0.55

  @impl true
  def name, do: "Presence"

  @impl true
  def init(display_info) do
    num_panels = max(div(display_info.width, @panel_width), 1)

    colors =
      for p <- 0..(num_panels - 1), into: %{} do
        {p, panel_color(p)}
      end

    level = for p <- 0..(num_panels - 1), into: %{}, do: {p, 0.0}

    %{colors: colors, level: level, ref: CrowdActivity.min_ref()}
  end

  @impl true
  def render(canvas, people, ctx, state) do
    dt = ctx.dt
    width = canvas.width
    height = canvas.height
    num_panels = max(div(width, @panel_width), 1)

    sensitivity = Map.get(ctx, :presence_sensitivity, 1.0)
    floor = Map.get(ctx, :presence_floor, 0.12) |> clamp01()
    smoothing = Map.get(ctx, :presence_smoothing, 0.4) |> clamp01()
    bleed = Map.get(ctx, :presence_bleed, 0.35) |> clamp01()
    adaptive = Map.get(ctx, :presence_adaptive, true)

    ring_outer = PanelMapping.ring_radius()
    raw = CrowdActivity.raw_factors(people, num_panels, ring_outer)

    ref = CrowdActivity.update_ref(state.ref, raw, adaptive, dt)

    target =
      for p <- 0..(num_panels - 1), into: %{} do
        {p, CrowdActivity.soft(sensitivity * Map.get(raw, p, 0.0) / ref)}
      end

    time_tau = lerp(0.15, 1.2, smoothing)
    alpha = 1.0 - :math.exp(-dt / time_tau)

    level =
      for p <- 0..(num_panels - 1), into: %{} do
        cur = Map.get(state.level, p, 0.0)
        {p, cur + (Map.fetch!(target, p) - cur) * alpha}
      end

    lit =
      for p <- 0..(num_panels - 1), into: %{} do
        left = Map.get(level, wrap(p - 1, num_panels), 0.0)
        right = Map.get(level, wrap(p + 1, num_panels), 0.0)
        {p, clamp01(Map.fetch!(level, p) + bleed * (left + right) / 2.0)}
      end

    canvas = paint(canvas, state.colors, lit, num_panels, height, floor)

    {canvas, %{state | level: level, ref: ref}}
  end

  defp paint(canvas, colors, lit, num_panels, height, floor) do
    Enum.reduce(0..(num_panels - 1), canvas, fn p, c ->
      brightness = floor + (1.0 - floor) * Map.fetch!(lit, p)
      color = scale(Map.fetch!(colors, p), brightness)
      x0 = p * @panel_width
      x1 = x0 + @panel_width - 1
      Canvas.fill_rect(c, {x0, 0}, {x1, height - 1}, color)
    end)
  end

  # Deterministic per-panel colour: same layout every boot, still looks random.
  defp panel_color(p) do
    hue = :math.fmod(p * 0.61803398875 + 0.13, 1.0)
    hsl_to_rgb(hue, @color_sat, @color_light)
  end

  defp wrap(p, n), do: rem(rem(p, n) + n, n)

  defp hsl_to_rgb(h, s, l) do
    if s == 0.0 do
      v = clamp_byte(l * 255.0)
      {v, v, v}
    else
      q = if l < 0.5, do: l * (1.0 + s), else: l + s - l * s
      p = 2.0 * l - q

      {hue_to_rgb(p, q, h + 1.0 / 3.0), hue_to_rgb(p, q, h), hue_to_rgb(p, q, h - 1.0 / 3.0)}
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

  defp scale({r, g, b}, f), do: {clamp_byte(r * f), clamp_byte(g * f), clamp_byte(b * f)}
  defp lerp(a, b, t), do: a + (b - a) * t
  defp clamp_byte(v), do: v |> trunc() |> max(0) |> min(255)
  defp clamp01(v), do: v |> max(0.0) |> min(1.0)
end
