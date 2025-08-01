defmodule Octopus.Sunlight do
  @moduledoc """
  Main Sunlight GenServer that coordinates automatic brightness adjustment based on solar data.

  This service:
  - Resolves location coordinates from installation config
  - Fetches daily solar data (sunrise, sunset times)
  - Calculates current brightness every 10 minutes
  - Updates device brightness via Octopus.Broadcaster
  - Provides circuit breaker protection for API failures
  - Manages retry logic and error recovery

  Inspired by the Fliplove.Weather service architecture.
  """

  use GenServer
  require Logger

  alias Phoenix.PubSub
  alias Octopus.{Installation, Broadcaster}
  alias Octopus.Sunlight.{LocationService, SolarService, BrightnessCalculator}

  defstruct [
    :location,
    :latitude,
    :longitude,
    :solar_data,
    :solar_data_timestamp,
    :last_brightness,
    :last_brightness_update,
    :last_error,
    :last_success,
    # Timers
    :brightness_timer,
    :solar_data_timer,
    :retry_timer,
    # Circuit breaker state
    :circuit_breaker_state,
    :failure_count,
    :last_failure_time,
    # Configuration
    :brightness_params,
    :enabled
  ]

  # Configuration constants
  # Update brightness every 10 minutes
  @brightness_update_interval :timer.minutes(10)
  # Update solar data twice daily
  @solar_data_update_interval :timer.hours(6)

  # Circuit breaker configuration
  @max_failures 3
  @circuit_breaker_timeout :timer.minutes(15)
  @retry_interval :timer.minutes(5)

  # GenServer call timeout
  @call_timeout 5_000

  @topic "sunlight:update"

  def topic, do: @topic

  # Client API

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %__MODULE__{}, name: __MODULE__)
  end

  def stop do
    GenServer.stop(__MODULE__)
  end

  @doc """
  Get the current calculated brightness value (0.0 to 1.0).
  """
  def get_current_brightness do
    try do
      GenServer.call(__MODULE__, :get_current_brightness, @call_timeout)
    catch
      :exit, {:timeout, _} ->
        Logger.warning("Sunlight service call timed out")
        nil

      :exit, {:noproc, _} ->
        Logger.warning("Sunlight service not available")
        nil

      :exit, reason ->
        Logger.warning("Sunlight service call failed: #{inspect(reason)}")
        nil
    end
  end

  @doc """
  Get the current solar data.
  """
  def get_solar_data do
    try do
      GenServer.call(__MODULE__, :get_solar_data, @call_timeout)
    catch
      :exit, {:timeout, _} ->
        Logger.warning("Sunlight service call timed out")
        nil

      :exit, {:noproc, _} ->
        Logger.warning("Sunlight service not available")
        nil

      :exit, reason ->
        Logger.warning("Sunlight service call failed: #{inspect(reason)}")
        nil
    end
  end

  @doc """
  Manually trigger a brightness update.
  """
  def update_brightness do
    try do
      GenServer.call(__MODULE__, :update_brightness, @call_timeout)
    catch
      :exit, {:timeout, _} ->
        Logger.warning("Sunlight service update call timed out")
        :error

      :exit, {:noproc, _} ->
        Logger.warning("Sunlight service not available for update")
        :error

      :exit, reason ->
        Logger.warning("Sunlight service update call failed: #{inspect(reason)}")
        :error
    end
  end

  @doc """
  Subscribe to sunlight updates.
  """
  def subscribe do
    PubSub.subscribe(Octopus.PubSub, topic())
  end

  # Server implementation

  @impl true
  def init(state) do
    Logger.debug("Initializing Sunlight service...")

    # Subscribe to configuration changes
    PubSub.subscribe(Octopus.PubSub, "sunlight:config")

    # Check if auto-brightness is enabled (installation config OR runtime global params)
    auto_brightness_enabled =
      Installation.auto_brightness() or Octopus.Params.Global.auto_brightness()

    if auto_brightness_enabled do
      Logger.info("Auto-brightness is enabled, starting sunlight service")

      with {:ok, {lat, lon}, source} <- resolve_location() do
        Logger.info("Sunlight service location: #{lat}, #{lon} (source: #{source})")

        # Initialize state
        initial_state = %{
          state
          | latitude: lat,
            longitude: lon,
            location: source,
            circuit_breaker_state: :closed,
            failure_count: 0,
            last_failure_time: nil,
            brightness_params: BrightnessCalculator.default_params(),
            enabled: true
        }

        # Schedule periodic updates
        {:ok, brightness_timer} =
          :timer.send_interval(@brightness_update_interval, :update_brightness)

        {:ok, solar_timer} = :timer.send_interval(@solar_data_update_interval, :update_solar_data)

        timer_state = %{
          initial_state
          | brightness_timer: brightness_timer,
            solar_data_timer: solar_timer
        }

        # Get initial solar data and calculate brightness immediately
        final_state =
          timer_state
          |> do_update_solar_data()
          |> do_update_brightness()

        Logger.info("Sunlight service started successfully")
        {:ok, final_state}
      else
        {:error, reason} ->
          Logger.error("Failed to resolve location for sunlight service: #{inspect(reason)}")
          Logger.info("Starting sunlight service in degraded mode, will retry")

          {:ok, retry_timer} = :timer.send_after(@retry_interval, :retry_initialization)

          degraded_state = %{
            state
            | circuit_breaker_state: :open,
              failure_count: @max_failures,
              last_failure_time: DateTime.utc_now(),
              retry_timer: retry_timer,
              enabled: true
          }

          {:ok, degraded_state}
      end
    else
      Logger.info("Auto-brightness is disabled, sunlight service inactive")
      {:ok, %{state | enabled: false}}
    end
  end

  @impl true
  def terminate(_reason, state) do
    if state.brightness_timer, do: :timer.cancel(state.brightness_timer)
    if state.solar_data_timer, do: :timer.cancel(state.solar_data_timer)
    if state.retry_timer, do: :timer.cancel(state.retry_timer)

    Logger.info("Terminating sunlight service")
  end

  # Server message handlers

  @impl true
  def handle_call(:get_current_brightness, _from, state) do
    {:reply, state.last_brightness, state}
  end

  @impl true
  def handle_call(:get_solar_data, _from, state) do
    {:reply, {state.solar_data, state.solar_data_timestamp}, state}
  end

  @impl true
  def handle_call(:update_brightness, _from, state) do
    new_state = do_update_brightness(state)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_info(:update_solar_data, state) do
    new_state = do_update_solar_data(state)
    {:noreply, new_state}
  rescue
    error ->
      Logger.error("Unexpected error updating solar data: #{inspect(error)}")
      new_state = record_failure(state, error)
      {:noreply, new_state}
  end

  @impl true
  def handle_info(:update_brightness, state) do
    new_state = do_update_brightness(state)
    {:noreply, new_state}
  rescue
    error ->
      Logger.error("Unexpected error updating brightness: #{inspect(error)}")
      new_state = record_failure(state, error)
      {:noreply, new_state}
  end

  @impl true
  def handle_info(:retry_initialization, state) do
    Logger.info("Retrying sunlight service initialization...")

    with {:ok, {lat, lon}, source} <- resolve_location() do
      Logger.info("Sunlight service initialization successful: #{lat}, #{lon} (#{source})")

      # Start timers
      {:ok, brightness_timer} =
        :timer.send_interval(@brightness_update_interval, :update_brightness)

      {:ok, solar_timer} = :timer.send_interval(@solar_data_update_interval, :update_solar_data)

      # Reset circuit breaker and update state
      new_state = %{
        state
        | latitude: lat,
          longitude: lon,
          location: source,
          brightness_timer: brightness_timer,
          solar_data_timer: solar_timer,
          circuit_breaker_state: :closed,
          failure_count: 0,
          last_failure_time: nil,
          retry_timer: nil,
          brightness_params: BrightnessCalculator.default_params()
      }

      # Try to get initial data
      final_state =
        new_state
        |> do_update_solar_data()
        |> do_update_brightness()

      {:noreply, final_state}
    else
      {:error, reason} ->
        Logger.warning("Sunlight service initialization still failing: #{inspect(reason)}")
        {:ok, retry_timer} = :timer.send_after(@retry_interval, :retry_initialization)
        {:noreply, %{state | retry_timer: retry_timer}}
    end
  end

  @impl true
  def handle_info(:retry_solar_service, state) do
    Logger.debug("Retrying solar service after circuit breaker timeout")

    new_state = %{state | circuit_breaker_state: :half_open, retry_timer: nil}
    final_state = do_update_solar_data(new_state)

    {:noreply, final_state}
  end

  @impl true
  def handle_info({:auto_brightness_changed, enabled}, state) do
    Logger.info("Auto-brightness setting changed to: #{enabled}")

    cond do
      enabled and not state.enabled ->
        # Auto-brightness was just enabled - start the service
        Logger.info("Enabling sunlight service")

        with {:ok, {lat, lon}, source} <- resolve_location() do
          Logger.info("Sunlight service starting: #{lat}, #{lon} (#{source})")

          # Start timers
          {:ok, brightness_timer} =
            :timer.send_interval(@brightness_update_interval, :update_brightness)

          {:ok, solar_timer} =
            :timer.send_interval(@solar_data_update_interval, :update_solar_data)

          # Update state
          new_state = %{
            state
            | latitude: lat,
              longitude: lon,
              location: source,
              brightness_timer: brightness_timer,
              solar_data_timer: solar_timer,
              circuit_breaker_state: :closed,
              failure_count: 0,
              last_failure_time: nil,
              retry_timer: nil,
              brightness_params: BrightnessCalculator.default_params(),
              enabled: true
          }

          # Get initial data
          final_state =
            new_state
            |> do_update_solar_data()
            |> do_update_brightness()

          {:noreply, final_state}
        else
          {:error, reason} ->
            Logger.warning("Failed to enable sunlight service: #{inspect(reason)}")
            {:noreply, %{state | enabled: false}}
        end

      not enabled and state.enabled ->
        # Auto-brightness was just disabled - stop the service
        Logger.info("Disabling sunlight service")

        # Cancel timers
        if state.brightness_timer, do: :timer.cancel(state.brightness_timer)
        if state.solar_data_timer, do: :timer.cancel(state.solar_data_timer)
        if state.retry_timer, do: :timer.cancel(state.retry_timer)

        # Reset state
        disabled_state = %{
          state
          | enabled: false,
            brightness_timer: nil,
            solar_data_timer: nil,
            retry_timer: nil,
            solar_data: nil,
            last_brightness: nil
        }

        {:noreply, disabled_state}

      true ->
        # No change needed
        {:noreply, state}
    end
  end

  # Private helper functions

  defp resolve_location do
    location_config = Installation.location()
    LocationService.resolve_location(location_config)
  end

  defp do_update_solar_data(%{enabled: false} = state), do: state
  defp do_update_solar_data(%{latitude: nil} = state), do: state

  defp do_update_solar_data(state) do
    if circuit_breaker_open?(state) do
      Logger.debug("Circuit breaker is open, skipping solar data update")
      state
    else
      Logger.debug("Fetching solar data from OpenMeteo...")

      case SolarService.get_solar_data(state.latitude, state.longitude) do
        {:ok, solar_data} ->
          timestamp = DateTime.utc_now()

          Logger.info(
            "Solar data retrieved from OpenMeteo API - sunrise: #{solar_data.sunrise}, sunset: #{solar_data.sunset}"
          )

          broadcast_solar_update(solar_data)

          new_state = record_success(state)
          %{new_state | solar_data: solar_data, solar_data_timestamp: timestamp}

        {:error, reason} ->
          Logger.warning("Failed to update solar data: #{inspect(reason)}")
          record_failure(state, reason)
      end
    end
  rescue
    error ->
      Logger.error("Unexpected error updating solar data: #{inspect(error)}")
      record_failure(state, error)
  end

  defp do_update_brightness(%{enabled: false} = state), do: state

  defp do_update_brightness(%{solar_data: nil} = state) do
    Logger.debug("No solar data available for brightness calculation")
    state
  end

  defp do_update_brightness(state) do
    current_time = DateTime.utc_now()

    brightness =
      BrightnessCalculator.calculate_brightness(
        state.solar_data,
        current_time,
        state.brightness_params
      )

    # Convert to device brightness (0-255)
    device_brightness = trunc(brightness * 255)

    Logger.info(
      "Auto brightness: calculated #{Float.round(brightness, 3)} (#{Float.round(brightness * 100, 1)}%), setting device brightness to #{device_brightness}/255"
    )

    # Update device brightness via broadcaster
    Broadcaster.set_luminance(device_brightness)

    # Update the global brightness parameter to reflect the auto-calculated value
    # This ensures the UI shows the current auto-brightness value
    Octopus.Params.put("global", "brightness", device_brightness)

    # Broadcast parameter update for UI sync
    Phoenix.PubSub.broadcast(
      Octopus.PubSub,
      "global_params",
      {:param_updated, :brightness, device_brightness}
    )

    # Broadcast update
    broadcast_brightness_update(brightness, device_brightness)

    %{
      state
      | last_brightness: brightness,
        last_brightness_update: current_time
    }
  rescue
    error ->
      Logger.error("Unexpected error calculating brightness: #{inspect(error)}")
      state
  end

  # Circuit breaker helper functions

  defp circuit_breaker_open?(state) do
    state.circuit_breaker_state == :open
  end

  defp record_success(state) do
    %{
      state
      | circuit_breaker_state: :closed,
        failure_count: 0,
        last_failure_time: nil,
        last_error: nil,
        last_success: DateTime.utc_now()
    }
  end

  defp record_failure(state, reason) do
    new_failure_count = state.failure_count + 1
    now = DateTime.utc_now()

    new_state = %{
      state
      | failure_count: new_failure_count,
        last_failure_time: now,
        last_error: reason,
        last_success: state.last_success
    }

    if new_failure_count >= @max_failures do
      Logger.warning("Circuit breaker opened after #{new_failure_count} failures")
      {:ok, retry_timer} = :timer.send_after(@circuit_breaker_timeout, :retry_solar_service)
      %{new_state | circuit_breaker_state: :open, retry_timer: retry_timer}
    else
      new_state
    end
  end

  defp broadcast_solar_update(solar_data) do
    PubSub.broadcast(Octopus.PubSub, topic(), {:solar_data_update, solar_data})
  rescue
    error ->
      Logger.error("Failed to broadcast solar data update: #{inspect(error)}")
      :error
  end

  defp broadcast_brightness_update(brightness, device_brightness) do
    PubSub.broadcast(Octopus.PubSub, topic(), {:brightness_update, brightness, device_brightness})
  rescue
    error ->
      Logger.error("Failed to broadcast brightness update: #{inspect(error)}")
      :error
  end
end
