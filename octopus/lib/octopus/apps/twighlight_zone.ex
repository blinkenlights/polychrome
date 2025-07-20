defmodule Octopus.Apps.TwighlightZone do
  use Octopus.App, category: :interactive
  require Logger

  alias Octopus.Canvas
  alias Octopus.Installation
  alias Octopus.PerlinNoise

  @fps 60
  @frame_time_ms trunc(1000 / @fps)

  def name, do: "Twighlight Zone"

  def compatible?() do
    installation_info = Octopus.App.get_installation_info()

    installation_info.panel_width >= 8 and
      installation_info.panel_height >= 8
  end

  defmodule State do
    defstruct panels: %{}, t: 0
  end

  def app_init(_args) do
    Octopus.App.configure_display(layout: :adjacent_panels)

    state = %State{t: 0}
    :timer.send_interval(@frame_time_ms, :tick)
    {:ok, state}
  end

  def handle_event(event, state) do
    Logger.info("Unhandled event: #{inspect(event)}")
    {:noreply, state}
  end

  def handle_info(
        :tick,
        %State{panels: panels, t: t} = state
      ) do
    panel_count = Installation.num_panels()
    panel_width = Installation.panel_width()
    panel_height = Installation.panel_height()

    width = panel_count * panel_width
    height = panel_height
    # 10 seconds per round
    move_period = 40 * @fps
    cx = rem(t, move_period) / move_period * width
    # cy: vertical center, wobbling around 2 pixels
    cy_base = height / 2
    cy_offset = :math.sin(2 * :math.pi() * rem(t, move_period) / move_period) * 2
    cy = cy_base + cy_offset
    num_arms = 12
    spiral_width = 0.18
    speed = 0.005
    angle_offset = t * speed

    big_canvas =
      Enum.reduce(0..(width - 1), Canvas.new(width, height), fn x, canvas ->
        Enum.reduce(0..(height - 1), canvas, fn y, c ->
          dx = x - cx
          dy = y - cy
          r = :math.sqrt(dx * dx + dy * dy)
          theta = :math.atan2(dy, dx)
          # Spirale
          v = :math.sin(num_arms * theta + r * spiral_width - angle_offset)

          # Perlin Noise
          noise = PerlinNoise.multi_octave_noise_3d(x * 0.12, y * 0.12, t * 0.03, 4, 0.5, 0)
          noise = (noise + 1) / 2

          base = if v > 0, do: 255, else: 0
          val = trunc(base * (0.7 + 0.3 * noise))
          # Clamp!
          val = max(0, min(val, 255))
          color = {val, val, val}
          Canvas.put_pixel(c, {x, y}, color)
        end)
      end)

    Octopus.App.update_display(big_canvas)
    {:noreply, %{state | panels: panels, t: t + 1}}
  end
end
