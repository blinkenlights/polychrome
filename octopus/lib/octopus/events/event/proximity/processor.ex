defmodule Octopus.Events.Event.Proximity.Processor do
  @moduledoc """
  Processes proximity events to add smoothing and filtering.

  Applies multiple smoothing algorithms (SMA, EMA, median filter, and combined)
  and returns enhanced events with all smoothed values for comparison.
  """

  use GenServer

  alias Octopus.Events.Event.Proximity, as: ProximityEvent

  @window_size 5
  # Smoothing factor for EMA (0.0 = very smooth, 1.0 = no smoothing)
  @ema_alpha 0.2
  # Distance threshold in mm - ignore events beyond this distance
  @distance_threshold 3000

  defmodule State do
    defstruct sensor_windows: %{}, sensor_ema_values: %{}, sensor_combined_ema_values: %{}
  end

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def process_event(%ProximityEvent{distance: distance}) when distance > @distance_threshold do
    :filtered
  end

  def process_event(%ProximityEvent{} = event) do
    event = GenServer.call(__MODULE__, {:process_event, event})

    {:ok, event}
  end

  # GenServer callbacks

  def init(:ok) do
    {:ok, %State{}}
  end

  def handle_call({:process_event, %ProximityEvent{} = event}, _from, %State{} = state) do
    sensor_key = {event.panel, event.sensor}

    # Get current window and EMA values for this sensor
    current_window = Map.get(state.sensor_windows, sensor_key, [])
    current_ema = Map.get(state.sensor_ema_values, sensor_key, event.distance)
    current_combined_ema = Map.get(state.sensor_combined_ema_values, sensor_key, event.distance)

    # Add new measurement and maintain window size
    new_window =
      [event.distance | current_window]
      |> Enum.take(@window_size)

    # Calculate different smoothing algorithms
    sma_value = calculate_simple_moving_average(new_window)
    ema_value = calculate_exponential_moving_average(event.distance, current_ema)
    median_value = calculate_median_filter(new_window)
    # Combined: median filter first, then EMA on clean values
    combined_value = calculate_exponential_moving_average(median_value, current_combined_ema)

    # Update state with new window and both EMA values
    new_state = %State{
      state
      | sensor_windows: Map.put(state.sensor_windows, sensor_key, new_window),
        sensor_ema_values: Map.put(state.sensor_ema_values, sensor_key, ema_value),
        sensor_combined_ema_values:
          Map.put(state.sensor_combined_ema_values, sensor_key, combined_value)
    }

    # Create enhanced event with all smoothed values
    enhanced_event = %ProximityEvent{
      event
      | distance_sma: sma_value,
        distance_ema: ema_value,
        distance_median: median_value,
        distance_combined: combined_value
    }

    {:reply, enhanced_event, new_state}
  end

  # Private helper functions

  defp calculate_simple_moving_average([]), do: 0.0

  defp calculate_simple_moving_average(values) do
    values
    |> Enum.sum()
    |> Kernel./(length(values))
  end

  defp calculate_exponential_moving_average(current_value, previous_ema) do
    @ema_alpha * current_value + (1 - @ema_alpha) * previous_ema
  end

  defp calculate_median_filter([]), do: 0.0

  defp calculate_median_filter(values) do
    sorted_values = Enum.sort(values)
    length = length(sorted_values)

    if rem(length, 2) == 1 do
      # Odd number of values - take middle value
      Enum.at(sorted_values, div(length, 2))
    else
      # Even number of values - average of two middle values
      mid1 = Enum.at(sorted_values, div(length, 2) - 1)
      mid2 = Enum.at(sorted_values, div(length, 2))
      (mid1 + mid2) / 2
    end
  end
end
