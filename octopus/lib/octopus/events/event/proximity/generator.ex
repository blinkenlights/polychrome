defmodule Octopus.Events.Event.Proximity.Generator do
  @moduledoc """
  Generator for creating test proximity events with realistic sensor patterns.

  Simulates ultrasonic sensor behavior including normal readings, spikes,
  and movement patterns for testing proximity algorithms.
  """

  use GenServer

  alias Octopus.Events.Event.Proximity, as: ProximityEvent
  alias Octopus.Events

  @default_config %{
    # Base distance in mm
    base_distance: 800.0,
    # Normal variation range (±mm)
    normal_variation: 50.0,
    # Spike probability (0.0 to 1.0, where 0.05 = 5% chance per event)
    spike_probability: 0.05,
    # Spike magnitude (mm above normal range)
    spike_magnitude: 1000.0,
    # Event generation interval (milliseconds)
    interval_ms: 100,
    # Panel and sensor configuration
    panels: [1],
    sensors: [0],
    # Movement simulation
    movement_enabled: true,
    # mm per event
    movement_speed: 2.0,
    # ±mm from base
    movement_range: 400.0
  }

  defmodule State do
    defstruct [
      :config,
      :timer_ref,
      :movement_offset,
      :movement_direction,
      :running
    ]
  end

  def init() do
    start_link(nil)
    start_generation()
  end

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @doc """
  Start generating proximity events with default configuration.
  """
  def start_generation() do
    start_generation(@default_config)
  end

  @doc """
  Start generating proximity events with custom configuration.
  """
  def start_generation(config) do
    GenServer.cast(__MODULE__, {:start_generation, config})
  end

  @doc """
  Stop generating proximity events.
  """
  def stop_generation() do
    GenServer.cast(__MODULE__, :stop_generation)
  end

  @doc """
  Get current generator status.
  """
  def status() do
    GenServer.call(__MODULE__, :status)
  end

  @doc """
  Generate a single test event manually.
  """
  def generate_single_event(panel \\ 1, sensor \\ 0) do
    GenServer.cast(__MODULE__, {:generate_single, panel, sensor})
  end

  # GenServer callbacks

  def init(:ok) do
    {:ok,
     %State{
       config: @default_config,
       movement_offset: 0.0,
       movement_direction: 1,
       running: false
     }}
  end

  def handle_cast({:start_generation, config}, %State{} = state) do
    if state.timer_ref, do: Process.cancel_timer(state.timer_ref)

    timer_ref = Process.send_after(self(), :generate_event, config.interval_ms)

    {:noreply,
     %State{
       state
       | config: Map.merge(@default_config, config),
         timer_ref: timer_ref,
         running: true
     }}
  end

  def handle_cast(:stop_generation, %State{} = state) do
    if state.timer_ref, do: Process.cancel_timer(state.timer_ref)

    {:noreply, %State{state | timer_ref: nil, running: false}}
  end

  def handle_cast({:generate_single, panel, sensor}, %State{} = state) do
    event = create_test_event(panel, sensor, state)
    Events.handle_event(event)
    {:noreply, state}
  end

  def handle_call(:status, _from, %State{} = state) do
    status = %{
      running: state.running,
      config: state.config,
      movement_offset: state.movement_offset
    }

    {:reply, status, state}
  end

  def handle_info(:generate_event, %State{running: true} = state) do
    # Generate events for all configured panels and sensors
    for panel <- state.config.panels,
        sensor <- state.config.sensors do
      event = create_test_event(panel, sensor, state)
      Events.handle_event(event)
    end

    # Update movement simulation
    new_state = update_movement(state)

    # Schedule next event
    timer_ref = Process.send_after(self(), :generate_event, state.config.interval_ms)

    {:noreply, %State{new_state | timer_ref: timer_ref}}
  end

  def handle_info(:generate_event, %State{running: false} = state) do
    # Generator was stopped, don't schedule next event
    {:noreply, state}
  end

  # Private functions

  defp create_test_event(panel, sensor, %State{} = state) do
    base_distance = calculate_base_distance(state)

    # Add normal variation
    normal_distance = base_distance + random_variation(state.config.normal_variation)

    # Possibly add spike
    final_distance = maybe_add_spike(normal_distance, state.config)

    %ProximityEvent{
      panel: panel,
      sensor: sensor,
      distance: final_distance,
      distance_sma: nil,
      distance_ema: nil,
      distance_median: nil,
      distance_combined: nil,
      timestamp: System.os_time(:millisecond)
    }
  end

  defp calculate_base_distance(%State{config: config, movement_offset: offset}) do
    if config.movement_enabled do
      config.base_distance + offset
    else
      config.base_distance
    end
  end

  defp random_variation(range) do
    (:rand.uniform() - 0.5) * 2 * range
  end

  defp maybe_add_spike(distance, config) do
    if :rand.uniform() < config.spike_probability do
      distance + config.spike_magnitude + :rand.uniform() * 1000
    else
      distance
    end
  end

  defp update_movement(%State{} = state) do
    if state.config.movement_enabled do
      new_offset = state.movement_offset + state.movement_direction * state.config.movement_speed

      # Reverse direction if we hit the movement range limits
      {new_offset, new_direction} =
        cond do
          new_offset > state.config.movement_range ->
            {state.config.movement_range, -1}

          new_offset < -state.config.movement_range ->
            {-state.config.movement_range, 1}

          true ->
            {new_offset, state.movement_direction}
        end

      %State{state | movement_offset: new_offset, movement_direction: new_direction}
    else
      state
    end
  end
end
