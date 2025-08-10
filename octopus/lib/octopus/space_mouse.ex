defmodule Octopus.SpaceMouse do
  @moduledoc """
  Public API for SpaceMouse integration in the Octopus system.

  This module provides a clean interface for apps to enable/disable SpaceMouse
  support and control device features like LED state. It mirrors the API of
  the underlying SpaceMouse driver library while integrating with the Octopus
  event system.

  ## Usage

  Apps that want to use SpaceMouse functionality should:

  1. Enable SpaceMouse support by calling `enable/0`
  2. Subscribe to SpaceMouse events through the normal Octopus event system
  3. Handle `Octopus.Events.Event.SpaceMouse` events in their event handlers
  4. Control the LED as needed using `set_led/1`
  5. Disable support when done with `disable/0`

  ## Example

      # In an app's init
      Octopus.SpaceMouse.enable()
      Octopus.SpaceMouse.set_led(:on)

      # In the app's event handler
      def handle_info({:event, %SpaceMouseEvent{type: :motion, motion: motion}}, state) do
        # Handle 6DOF motion data
        handle_spacemouse_motion(motion, state)
      end

      def handle_info({:event, %SpaceMouseEvent{type: :button, button: button}}, state) do
        # Handle button press/release
        handle_spacemouse_button(button, state)
      end

      # When app stops
      Octopus.SpaceMouse.set_led(:off)
      Octopus.SpaceMouse.disable()

  """

  use GenServer
  require Logger

  alias Octopus.SpaceMouse.Adapter

  defmodule State do
    @moduledoc false
    defstruct [:enabled, :apps_using_spacemouse]
  end

  @doc """
  Starts the SpaceMouse subsystem.
  """
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @doc """
  Enables SpaceMouse support.

  This starts monitoring for SpaceMouse devices and begins sending events
  to the Octopus event system. Multiple apps can call this safely - the
  system keeps track of which apps are using SpaceMouse.
  """
  def enable do
    GenServer.call(__MODULE__, :enable)
  end

  @doc """
  Disables SpaceMouse support.

  This stops monitoring SpaceMouse devices. If multiple apps are using
  SpaceMouse, the system will only stop monitoring when all apps have
  called disable.
  """
  def disable do
    GenServer.call(__MODULE__, :disable)
  end

  @doc """
  Sets the SpaceMouse LED state.

  ## Parameters

  - `state` - `:on` to turn the LED on, `:off` to turn it off

  Returns `:ok` if successful, `{:error, reason}` if failed.
  """
  def set_led(state) when state in [:on, :off] do
    GenServer.call(__MODULE__, {:set_led, state})
  end

  @doc """
  Gets the current LED state.

  Returns `:on`, `:off`, or `:unknown` if the state is not known.
  """
  def get_led_state do
    GenServer.call(__MODULE__, :get_led_state)
  end

  @doc """
  Checks if SpaceMouse support is currently enabled.
  """
  def enabled? do
    GenServer.call(__MODULE__, :enabled?)
  end

  @doc """
  Gets information about connected SpaceMouse devices.

  Returns a list of device information maps.
  """
  def get_device_info do
    GenServer.call(__MODULE__, :get_device_info)
  end

  @doc """
  Subscribe to SpaceMouse subsystem events for debugging or monitoring.

  This is separate from the main event system and is mainly for debugging.
  Apps should use the normal Octopus event system to receive SpaceMouse events.
  """
  def subscribe do
    Adapter.subscribe()
  end

  @impl true
  def init(:ok) do
    {:ok, %State{enabled: false, apps_using_spacemouse: MapSet.new()}}
  end

  @impl true
  def handle_call(:enable, {from_pid, _ref}, state) do
    # Add the calling process to the set of apps using SpaceMouse
    new_apps = MapSet.put(state.apps_using_spacemouse, from_pid)

    # Monitor the calling process so we can clean up if it dies
    Process.monitor(from_pid)

    # If this is the first app to enable SpaceMouse, start monitoring
    result =
      if not state.enabled do
        case SpaceMouse.start_monitoring() do
          :ok ->
            Logger.info("SpaceMouse monitoring started")
            :ok

          {:error, reason} ->
            Logger.error("Failed to start SpaceMouse monitoring: #{inspect(reason)}")
            {:error, reason}
        end
      else
        :ok
      end

    case result do
      :ok ->
        new_state = %State{state | enabled: true, apps_using_spacemouse: new_apps}
        {:reply, :ok, new_state}

      error ->
        {:reply, error, state}
    end
  end

  def handle_call(:disable, {from_pid, _ref}, state) do
    # Remove the calling process from the set of apps using SpaceMouse
    new_apps = MapSet.delete(state.apps_using_spacemouse, from_pid)

    # If no apps are using SpaceMouse anymore, stop monitoring
    {result, enabled} =
      if MapSet.size(new_apps) == 0 and state.enabled do
        case SpaceMouse.stop_monitoring() do
          :ok ->
            Logger.info("SpaceMouse monitoring stopped")
            {:ok, false}

          {:error, reason} ->
            Logger.error("Failed to stop SpaceMouse monitoring: #{inspect(reason)}")
            {{:error, reason}, true}
        end
      else
        {:ok, state.enabled}
      end

    new_state = %State{state | enabled: enabled, apps_using_spacemouse: new_apps}
    {:reply, result, new_state}
  end

  def handle_call({:set_led, led_state}, _from, state) do
    if state.enabled do
      result = SpaceMouse.set_led(led_state)
      {:reply, result, state}
    else
      {:reply, {:error, :not_enabled}, state}
    end
  end

  def handle_call(:get_led_state, _from, state) do
    if state.enabled do
      led_state = Adapter.get_led_state()
      {:reply, led_state, state}
    else
      {:reply, :unknown, state}
    end
  end

  def handle_call(:enabled?, _from, state) do
    {:reply, state.enabled, state}
  end

  def handle_call(:get_device_info, _from, state) do
    if state.enabled do
      # Try to get device info from the SpaceMouse library
      # This might not be directly available, so we'll return what we can
      device_info = []
      {:reply, device_info, state}
    else
      {:reply, [], state}
    end
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    # A monitored process (app) died, remove it from our set
    new_apps = MapSet.delete(state.apps_using_spacemouse, pid)

    # If no apps are using SpaceMouse anymore, stop monitoring
    {enabled, _result} =
      if MapSet.size(new_apps) == 0 and state.enabled do
        case SpaceMouse.stop_monitoring() do
          :ok ->
            Logger.info("SpaceMouse monitoring stopped (last app died)")
            {false, :ok}

          {:error, reason} ->
            Logger.error("Failed to stop SpaceMouse monitoring: #{inspect(reason)}")
            {true, {:error, reason}}
        end
      else
        {state.enabled, :ok}
      end

    new_state = %State{state | enabled: enabled, apps_using_spacemouse: new_apps}
    {:noreply, new_state}
  end

  def handle_info(message, state) do
    Logger.debug("#{__MODULE__}: Unhandled message: #{inspect(message)}")
    {:noreply, state}
  end
end
