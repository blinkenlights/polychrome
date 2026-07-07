defmodule Octopus.Apps.Collective.Animations.LavaLamp do
  @moduledoc """
  Lava Lamp — cylindrical metaball blobs on the LED ring.

  Slow sinusoidal rise/fall, soft sigmoid colouring, seamless wrap at panel 12→1.
  No crowd input.
  """

  @behaviour Octopus.Apps.Collective.Animation

  alias Octopus.Canvas
  alias Octopus.Installation

  @two_pi 2.0 * :math.pi()
  @field_softness 0.35

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

  @impl true
  def name, do: "Lava Lamp"

  @impl true
  def init(_display_info) do
    count = 7

    %{
      t: 0.0,
      blob_count: count,
      blobs: generate_blobs(count)
    }
  end

  @impl true
  def render(canvas, _people, ctx, state) do
    dt = ctx.dt
    speed = Map.get(ctx, :lava_speed, 1.0) |> clamp(0.2, 3.0)
    size_mul = Map.get(ctx, :lava_size_mul, 1.25) |> clamp(0.6, 2.2)
    thresh = Map.get(ctx, :lava_thresh, 0.9) |> clamp(0.4, 1.6)
    palette = palette_stops(Map.get(ctx, :lava_palette, :classic))
    blob_count = Map.get(ctx, :lava_blob_count, 7) |> clamp_int(3, 12)

    state = ensure_blobs(state, blob_count)
    t = state.t + dt
    t_anim = t * speed

    width = canvas.width
    height = canvas.height
    circumference = width

    canvas =
      for x <- 0..(width - 1), y <- 0..(height - 1), reduce: canvas do
        acc ->
          theta_px = x / circumference * @two_pi
          field = field_at(theta_px, y, t_anim, state.blobs, circumference, size_mul)
          color = pixel_color(field, y, height, thresh, palette)
          Canvas.put_pixel(acc, {x, y}, color)
      end

    {canvas, %{state | t: t}}
  end

  @doc false
  def field_at(theta_px, y, t, blobs, circumference, size_mul \\ 1.25) do
    k = circumference / @two_pi

    Enum.reduce(blobs, 0.0, fn blob, acc ->
      {theta_blob, y_blob, radius} = blob_pose(blob, t, size_mul)
      dth = angular_dist(theta_px, theta_blob)
      dx = dth * k
      dy = (y - y_blob) * 1.15
      r2 = radius * radius
      acc + r2 / (dx * dx + dy * dy + @field_softness)
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
  def generate_blobs(count) do
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

  defp ensure_blobs(%{blob_count: existing} = state, existing), do: state

  defp ensure_blobs(state, count) do
    %{state | blob_count: count, blobs: generate_blobs(count)}
  end

  defp blob_pose(blob, t, size_mul) do
    y_blob = 3.5 + blob.y_amp * :math.sin(@two_pi * t / blob.y_period + blob.y_phase)

    theta_blob =
      blob.theta0 + blob.drift * t +
        0.12 * :math.sin(@two_pi * t / blob.wob_period + blob.wob_phase)

    radius =
      blob.r * size_mul *
        (1 + 0.18 * :math.sin(@two_pi * t / blob.pulse_period + blob.pulse_phase))

    {theta_blob, y_blob, radius}
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
    {r2, g2, b2} = Enum.at(stops, i + 1)

    {round(lerp(r1, r2, t)), round(lerp(g1, g2, t)), round(lerp(b1, b2, t))}
  end

  defp rand_uniform(a, b), do: a + :rand.uniform() * (b - a)

  defp lerp(a, b, t), do: a + (b - a) * t
  defp clamp(v, lo, hi), do: v |> max(lo) |> min(hi)
  defp clamp_int(v, lo, hi), do: v |> trunc() |> max(lo) |> min(hi)
end
