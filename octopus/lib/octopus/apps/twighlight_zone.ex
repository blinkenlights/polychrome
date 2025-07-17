defmodule Octopus.Apps.TwighlightZone do
  use Octopus.App, category: :interactive
  require Logger

  alias Octopus.Canvas
  alias Octopus.Installation

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
    panel_count = Installation.num_panels()
    panel_width = Installation.panel_width()
    panel_height = Installation.panel_height()

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
    cx = width / 2
    cy = height / 2
    num_arms = 12
    spiral_width = 0.18
    speed = 0.08
    angle_offset = t * speed

    big_canvas =
      Enum.reduce(0..(width-1), Canvas.new(width, height), fn x, canvas ->
        Enum.reduce(0..(height-1), canvas, fn y, c ->
          dx = x - cx
          dy = y - cy
          r = :math.sqrt(dx * dx + dy * dy)
          theta = :math.atan2(dy, dx)
          # Spirale: abwechselnd schwarz/weiß
          v = :math.sin(num_arms * theta + r * spiral_width - angle_offset)
          color = if v > 0, do: {255, 255, 255}, else: {0, 0, 0}
          Canvas.put_pixel(c, {x, y}, color)
        end)
      end)

    Octopus.App.update_display(big_canvas)
    {:noreply, %{state | panels: panels, t: t + 1}}
  end
end
