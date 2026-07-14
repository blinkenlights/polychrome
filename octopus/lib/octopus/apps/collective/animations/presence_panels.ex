defmodule Octopus.Apps.Collective.Animations.PresencePanels do
  @moduledoc """
  Presence — each panel glows fully in a fixed random colour; brightness follows
  the shared per-panel activity factors from `Octopus.Radar.PanelActivity`.

  Neighbour bleed and base glow are visual-only tuning on top of the service
  output.
  """

  @behaviour Octopus.Apps.Collective.Animation

  alias Octopus.Canvas
  alias Octopus.Radar

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

    %{colors: colors}
  end

  @impl true
  def render(canvas, _people, ctx, state) do
    width = canvas.width
    height = canvas.height
    num_panels = max(div(width, @panel_width), 1)

    floor = Map.get(ctx, :presence_floor, 0.0) |> clamp01()
    bleed = Map.get(ctx, :presence_bleed, 0.35) |> clamp01()

    factors = Radar.panel_factors()

    lit =
      for frame_panel <- 0..(num_panels - 1), into: %{} do
        install_panel = frame_panel + 1
        base = Map.get(factors, install_panel, 0.0)

        left = Map.get(factors, wrap_install_panel(install_panel - 1, num_panels), 0.0)
        right = Map.get(factors, wrap_install_panel(install_panel + 1, num_panels), 0.0)

        {frame_panel, {base, clamp01(base + bleed * (left + right) / 2.0)}}
      end

    canvas = paint(canvas, state.colors, lit, num_panels, height, floor)

    {canvas, state}
  end

  defp paint(canvas, colors, lit, num_panels, height, floor) do
    Enum.reduce(0..(num_panels - 1), canvas, fn p, c ->
      {base, level} = Map.fetch!(lit, p)
      brightness = floor + (1.0 - floor) * level

      color =
        if base <= 0.0 do
          {0, 0, 0}
        else
          scale(Map.fetch!(colors, p), brightness)
        end

      x0 = p * @panel_width
      x1 = x0 + @panel_width - 1
      Canvas.fill_rect(c, {x0, 0}, {x1, height - 1}, color)
    end)
  end

  defp wrap_install_panel(panel, num_panels) do
    rem(rem(panel - 1, num_panels) + num_panels, num_panels) + 1
  end

  # Deterministic per-panel colour: same layout every boot, still looks random.
  defp panel_color(p) do
    hue = :math.fmod(p * 0.61803398875 + 0.13, 1.0)
    hsl_to_rgb(hue, @color_sat, @color_light)
  end

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
  defp clamp_byte(v), do: v |> trunc() |> max(0) |> min(255)
  defp clamp01(v), do: v |> max(0.0) |> min(1.0)
end
