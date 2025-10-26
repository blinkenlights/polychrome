defmodule Octopus.Apps.ProximityDemo do
  use Octopus.App, category: :test
  require Logger

  alias Octopus.Installation
  alias Octopus.Canvas
  alias Octopus.Events.Event.Proximity, as: ProximityEvent

  defmodule State do
    defstruct [:proximity_events]
  end

  @fps 60
  @frame_time_ms trunc(1000 / @fps)

  @min_distance 300
  @max_distance 2000

  @fade_time_ms 5000

  def name(), do: "Proximity Demo"

  def app_init(_) do
    Octopus.App.configure_display(layout: :adjacent_panels)
    :timer.send_interval(@frame_time_ms, :tick)

    {:ok, %State{proximity_events: %{}}}
  end

  def handle_event(%ProximityEvent{} = event, %State{} = state) do
    key = {event.panel, event.sensor}
    state = %State{state | proximity_events: Map.put(state.proximity_events, key, event)}

    {:noreply, state}
  end

  def handle_event(_any_event, %State{} = state) do
    {:noreply, state}
  end

  def handle_info(:tick, %State{} = state) do
    display_info = Octopus.App.get_display_info()
    canvas = Canvas.new(display_info.width, display_info.height)
    current_time = System.os_time(:millisecond)

    Enum.reduce(state.proximity_events, canvas, fn {_, event}, acc_canvas ->
      render_event(acc_canvas, display_info, event, current_time)
    end)
    |> Octopus.App.update_display()

    {:noreply, state}
  end

  def handle_info(_any_info, %State{} = state) do
    {:noreply, state}
  end

  defp render_event(%Canvas{} = canvas, display_info, %ProximityEvent{} = event, current_time) do
    time_since_event = current_time - event.timestamp

    saturation = saturation(event.distance)
    value = value(time_since_event)

    render_panel_side(canvas, display_info, event.panel, event.sensor, saturation, value)
  end

  defp saturation(distance) do
    case distance do
      d when d < @min_distance ->
        100

      d when d > @max_distance ->
        0

      d ->
        ratio = (d - @min_distance) / (@max_distance - @min_distance)
        trunc((1.0 - ratio) * 100)
    end
  end

  defp value(time_since_event) do
    case time_since_event do
      t when t >= @fade_time_ms ->
        0

      t ->
        # Linear fade from 100 to 0 over fade_time_ms
        ratio = t / @fade_time_ms
        trunc((1.0 - ratio) * 100)
    end
  end

  defp render_panel_side(canvas, display_info, panel_index, sensor, saturation, value) do
    # Convert HSV to RGB
    hue = 360 * panel_index / Installation.num_panels()
    hue = :math.fmod(hue, 360)

    %Chameleon.RGB{r: r, g: g, b: b} =
      Chameleon.HSV.new(hue, saturation, value)
      |> Chameleon.convert(Chameleon.RGB)

    color = {r, g, b}

    # Panel index 1 corresponds to the first panel, so subtract 1
    panel_start_x = (panel_index - 1) * display_info.panel_width
    side_width = div(display_info.panel_width, 2)

    # sensor: 0 = right side, 1 = left side
    x_start = panel_start_x + if sensor == 0, do: side_width, else: 0
    x_end = x_start + side_width - 1

    for x <- x_start..x_end,
        y <- 0..(display_info.panel_height - 1),
        reduce: canvas do
      canvas ->
        Canvas.put_pixel(canvas, {x, y}, color)
    end
  end
end
