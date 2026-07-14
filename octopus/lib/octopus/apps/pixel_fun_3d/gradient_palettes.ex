defmodule Octopus.Apps.PixelFun3D.GradientPalettes do
  @moduledoc false

  alias Octopus.Installation

  @palettes %{
    rainbow: [
      {255, 0, 0},
      {255, 128, 0},
      {255, 255, 0},
      {0, 255, 0},
      {0, 255, 255},
      {0, 0, 255},
      {128, 0, 255},
      {255, 0, 128}
    ],
    sunset: [
      {35, 10, 55},
      {90, 15, 80},
      {180, 40, 30},
      {255, 100, 20},
      {255, 170, 50},
      {255, 220, 140}
    ],
    ocean: [
      {4, 12, 40},
      {8, 45, 95},
      {15, 100, 150},
      {30, 160, 185},
      {80, 200, 215},
      {180, 235, 245},
      {230, 248, 255}
    ],
    wood: [
      {25, 12, 6},
      {50, 28, 12},
      {85, 48, 20},
      {125, 78, 32},
      {165, 115, 52},
      {210, 175, 95},
      {235, 210, 155}
    ],
    desert: [
      {55, 35, 20},
      {100, 65, 30},
      {150, 100, 45},
      {195, 150, 75},
      {230, 195, 120},
      {255, 235, 185},
      {255, 248, 220}
    ],
    rainforest: [
      {6, 18, 8},
      {12, 45, 18},
      {20, 85, 28},
      {35, 130, 42},
      {70, 175, 58},
      {130, 210, 80},
      {200, 235, 110},
      {235, 248, 170}
    ]
  }

  @palette_names Map.keys(@palettes)

  def palette_names, do: @palette_names

  def palette(name) when is_atom(name) do
    Map.get(@palettes, name, Map.fetch!(@palettes, :rainbow))
  end

  def gradient_t(x, y) do
    w = max(Installation.width(), 1) * 1.0
    h = max(Installation.height(), 1) * 1.0

    x_frac = (x + w / 2) / w
    y_frac = (y + h / 2) / h

    (x_frac * 0.667 + y_frac * 0.333) |> max(0.0) |> min(1.0)
  end

  def color_at(x, y, palette_name) when is_atom(palette_name) do
    palette_color(palette(palette_name), gradient_t(x, y))
  end

  def pixel_color(_x, _y, _palette_name, value, _saturation_percent, _gain)
      when value == 0.0,
      do: {0, 0, 0}

  def pixel_color(x, y, palette_name, value, saturation_percent, gain) do
    {r, g, b} = color_at(x, y, palette_name)
    apply_tone({r, g, b}, value, saturation_percent, gain)
  end

  def apply_tone(_rgb, value, _saturation_percent, _gain) when value == 0.0, do: {0, 0, 0}

  def apply_tone({r, g, b}, value, saturation_percent, gain) do
    brightness = gain * abs(value) / 100.0
    sat = saturation_percent |> max(0) |> min(100) |> Kernel./(100.0)

    grey = 0.299 * r + 0.587 * g + 0.114 * b

    r = (r * sat + grey * (1.0 - sat)) * brightness
    g = (g * sat + grey * (1.0 - sat)) * brightness
    b = (b * sat + grey * (1.0 - sat)) * brightness

    {clamp_channel(r), clamp_channel(g), clamp_channel(b)}
  end

  defp clamp_channel(v),
    do: v |> round() |> max(0) |> min(255)

  defp palette_color(stops, v) do
    n = length(stops)
    x = v |> max(0.0) |> min(0.9999) |> Kernel.*(n - 1)
    i = trunc(x)
    t = x - i
    {r1, g1, b1} = Enum.at(stops, i)
    {r2, g2, b2} = Enum.at(stops, min(i + 1, n - 1))

    {round(lerp(r1, r2, t)), round(lerp(g1, g2, t)), round(lerp(b1, b2, t))}
  end

  defp lerp(a, b, t), do: a + (b - a) * t
end
