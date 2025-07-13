defmodule Octopus.Apps.ProximityDemo do
  use Octopus.App, category: :test
  require Logger

  alias Octopus.Canvas
  alias Octopus.Events.Event.Proximity, as: ProximityEvent

  defmodule State do
    defstruct [:min_distance, :max_distance]
  end

  @fps 30
  @frame_time_ms trunc(1000 / @fps)

  # Smoothing factor for exponential moving average (0.0 to 1.0)
  # Lower values = more smoothing, higher values = more responsive
  # @smoothing_factor 0.1

  def name(), do: "Proximity Demo"

  def config_schema() do
    %{
      min_distance: {"Min Distance [mm]", :int, %{default: 500, min: 0, max: 50_000}},
      max_distance: {"Max Distance [mm]", :int, %{default: 3_000, min: 0, max: 50_000}}
    }
  end

  def get_config(state) do
    %{
      min_distance: state.min_distance,
      max_distance: state.max_distance
    }
  end

  def handle_config_change(config, state) do
    {:ok, %State{state | min_distance: config.min_distance, max_distance: config.max_distance}}
  end

  def app_init(config) do
    # Configure display using new unified API - adjacent layout for proximity sensors
    Octopus.App.configure_display(layout: :adjacent_panels)

    # # Start the timer for rendering
    # :timer.send_interval(@frame_time_ms, :tick)

    {:ok,
     %State{
       min_distance: config.min_distance,
       max_distance: config.max_distance
     }}
  end

  # def handle_info(:tick, %State{} = state) do
  #   state
  #   |> render_proximity_data()
  #   |> Octopus.App.update_display()

  #   {:noreply, state}
  # end

  def handle_event(%ProximityEvent{} = event, state) do
    state
    |> render_proximity_data(event)
    |> Octopus.App.update_display()

    {:noreply, state}
  end

  def handle_event(any_event, state) do
    {:noreply, state}
  end

  defp render_proximity_data(
         %State{min_distance: min, max_distance: max},
         %ProximityEvent{distance: distance, panel: panel_index, sensor: sensor_index} = event
       ) do
    # Get display info to use correct dimensions
    display_info = Octopus.App.get_display_info()
    canvas = Canvas.new(display_info.width, display_info.height)

    # Get all smoothed readings from the ProximitySensor
    # smoothed_measurements = Octopus.ProximitySensor.get_smoothed_values()
    # smoothed_measurements = []

    # Enum.reduce(smoothed_measurements, canvas, fn {{panel_index, sensor_index}, distance},
    #                                               acc_canvas ->
    brightness_ratio = 1.0 - (distance - min) / (max - min)
    brightness_value = trunc(brightness_ratio * 100)

    %Chameleon.RGB{r: r, g: g, b: b} =
      Chameleon.HSV.new(280, 100, brightness_value)
      |> Chameleon.convert(Chameleon.RGB)

    color = {r, g, b}

    panel_start_x = panel_index * display_info.panel_width
    side_width = div(display_info.panel_width, 2)

    # Sensor 0 = left side, Sensor 1 = right side
    x_start = panel_start_x + if sensor_index == 0, do: 0, else: side_width
    x_end = x_start + side_width - 1

    for x <- x_start..x_end,
        y <- 0..(display_info.panel_height - 1),
        reduce: canvas do
      canvas -> Canvas.put_pixel(canvas, {x, y}, color)
    end

    # end)
  end
end
