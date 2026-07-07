defmodule Octopus.Apps.Collective.Animations.RingNoise do
  @moduledoc """
  Ring Noise — seamless cylindrical noise with palette colours and counter-rotating
  brightness waves. No crowd input; the ring panels read as one wrapped surface.
  """

  @behaviour Octopus.Apps.Collective.Animation

  alias Octopus.Canvas
  alias Octopus.Installation

  @two_pi 2.0 * :math.pi()

  # Deterministic octave coefficients (seed {42, 1337, 9001}, one-time generation).
  @octaves [
    {-1.592737, -1.495191, 0.174253, 0.27016, 0.792633, 1.0},
    {-1.375006, -1.902454, -0.712577, -0.622185, 1.272427, 0.5},
    {-2.196426, -0.08896, 0.86786, 0.220862, 2.38649, 0.333333},
    {-3.097652, -2.251249, -0.119193, -0.570967, 3.686119, 0.25},
    {-3.982441, 6.162484, -0.341557, 0.646226, 0.431916, 0.2}
  ]

  @weight_sum Enum.reduce(@octaves, 0.0, fn {_a, _b, _c, _d, _p, w}, acc -> acc + w end)

  @palettes %{
    lava: [{26, 5, 51}, {74, 13, 110}, {157, 25, 133}, {221, 58, 111}, {248, 124, 58}, {255, 196, 92}],
    ocean: [{4, 10, 38}, {8, 42, 92}, {13, 94, 140}, {29, 158, 145}, {93, 202, 165}, {225, 245, 238}],
    aurora: [{8, 6, 30}, {20, 28, 70}, {15, 110, 86}, {93, 202, 120}, {212, 83, 126}, {244, 192, 209}]
  }

  @impl true
  def name, do: "Ring Noise"

  @impl true
  def init(_display_info), do: %{start_ms: :erlang.monotonic_time(:millisecond)}

  @impl true
  def render(canvas, _people, ctx, state) do
    width = canvas.width
    height = canvas.height
    t = elapsed_seconds(state)
    noise_speed = Map.get(ctx, :ring_noise_speed, 1.0)
    pulse_period = Map.get(ctx, :ring_noise_pulse_period, 24.0)
    pulse_amount = Map.get(ctx, :ring_noise_pulse_amount, 0.65) |> clamp01()
    counter_wave = Map.get(ctx, :ring_noise_counter_wave, true)
    palette = palette_stops(Map.get(ctx, :ring_noise_palette, :lava))

    canvas =
      for x <- 0..(width - 1), y <- 0..(height - 1), reduce: canvas do
        acc ->
          theta = x / width * @two_pi
          br = brightness(theta, t, pulse_period, pulse_amount, counter_wave)
          v = noise(theta, y * 0.9, t * noise_speed)
          {r, g, b} = palette_color(palette, v)
          Canvas.put_pixel(acc, {x, y}, {round(r * br), round(g * br), round(b * br)})
      end

    {canvas, state}
  end

  @doc false
  def noise(theta, y, t) do
    cx = :math.cos(theta)
    sx = :math.sin(theta)

    s =
      Enum.reduce(@octaves, 0.0, fn {a, b, c, d, phase, w}, acc ->
        acc + w * :math.sin(a * cx + b * sx + c * y + d * t + phase)
      end)

    raw = 0.5 + 0.5 * (s / @weight_sum) * 1.6
    raw |> max(0.0) |> min(1.0)
  end

  @doc false
  def brightness(theta, t, pulse_period, pulse_amount, counter_wave \\ true) do
    w1 =
      :math.pow(0.5 + 0.5 * :math.sin(theta - t * @two_pi / pulse_period), 2.2)

    w =
      if counter_wave do
        w2 =
          :math.pow(
            0.5 + 0.5 * :math.sin(-theta - t * @two_pi / (pulse_period * 1.37) + 2.1),
            2.2
          )

        min(1.0, w1 + 0.8 * w2)
      else
        w1
      end

    (1.0 - pulse_amount) + pulse_amount * w
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

  defp elapsed_seconds(%{start_ms: start_ms}) do
    (:erlang.monotonic_time(:millisecond) - start_ms) / 1000.0
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
    {r2, g2, b2} = Enum.at(stops, i + 1)

    {lerp(r1, r2, t), lerp(g1, g2, t), lerp(b1, b2, t)}
  end

  defp lerp(a, b, t), do: a + (b - a) * t
  defp clamp01(v), do: v |> max(0.0) |> min(1.0)
end
