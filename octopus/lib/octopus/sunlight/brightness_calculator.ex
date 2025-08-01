defmodule Octopus.Sunlight.BrightnessCalculator do
  @moduledoc """
  Pure function module for calculating sunlight-based brightness curves.

  This module provides functions to calculate brightness values (0.0 to 1.0) based on:
  - Current time relative to sunrise/sunset
  - Solar elevation angle (if available)
  - Configurable curve parameters for dawn/dusk transitions
  - Seasonal adjustments

  The brightness curve simulates natural sunlight availability with smooth transitions
  during dawn and dusk periods.
  """

  require Logger

  # Default curve parameters
  # Duration of dawn transition in minutes
  @default_dawn_duration_minutes 60
  # Duration of dusk transition in minutes
  @default_dusk_duration_minutes 60
  # Minimum brightness (night)
  @default_min_brightness 0.0
  # Maximum brightness (noon)
  @default_max_brightness 1.0
  # Brightness at end of dawn
  @default_dawn_brightness 0.1
  # Brightness at start of dusk
  @default_dusk_brightness 0.1

  @type solar_data :: %{
          sunrise: DateTime.t(),
          sunset: DateTime.t(),
          solar_noon: DateTime.t(),
          day_length: integer()
        }

  @type brightness_params :: %{
          dawn_duration_minutes: integer(),
          dusk_duration_minutes: integer(),
          min_brightness: float(),
          max_brightness: float(),
          dawn_brightness: float(),
          dusk_brightness: float()
        }

  @doc """
  Calculate the current brightness value based on solar data and current time.

  Returns a float between 0.0 (no sunlight) and 1.0 (full sunlight).

  ## Examples

      iex> solar_data = %{
      ...>   sunrise: ~U[2024-01-15 07:42:00Z],
      ...>   sunset: ~U[2024-01-15 15:58:00Z],
      ...>   solar_noon: ~U[2024-01-15 11:50:00Z],
      ...>   day_length: 29760
      ...> }
      iex> calculate_brightness(solar_data, ~U[2024-01-15 12:00:00Z])
      1.0

      iex> calculate_brightness(solar_data, ~U[2024-01-15 02:00:00Z])
      0.0
  """
  def calculate_brightness(solar_data, current_time \\ DateTime.utc_now(), params \\ %{}) do
    params = merge_default_params(params)

    # Calculate time positions relative to solar events
    sunrise_time = solar_data.sunrise
    sunset_time = solar_data.sunset
    solar_noon_time = solar_data.solar_noon

    # Create dawn and dusk transition periods
    dawn_start = DateTime.add(sunrise_time, -params.dawn_duration_minutes * 60, :second)
    dawn_end = sunrise_time
    dusk_start = sunset_time
    dusk_end = DateTime.add(sunset_time, params.dusk_duration_minutes * 60, :second)

    cond do
      # Before dawn - night time
      DateTime.compare(current_time, dawn_start) == :lt ->
        params.min_brightness

      # Dawn transition period
      DateTime.compare(current_time, dawn_start) != :lt and
          DateTime.compare(current_time, dawn_end) == :lt ->
        calculate_dawn_brightness(current_time, dawn_start, dawn_end, params)

      # Day time (sunrise to sunset)
      DateTime.compare(current_time, dawn_end) != :lt and
          DateTime.compare(current_time, dusk_start) == :lt ->
        calculate_day_brightness(current_time, sunrise_time, sunset_time, solar_noon_time, params)

      # Dusk transition period
      DateTime.compare(current_time, dusk_start) != :lt and
          DateTime.compare(current_time, dusk_end) == :lt ->
        calculate_dusk_brightness(current_time, dusk_start, dusk_end, params)

      # After dusk - night time
      true ->
        params.min_brightness
    end
  end

  @doc """
  Calculate brightness using solar elevation angle for more precise results.

  This provides a more accurate brightness calculation when solar elevation data is available.
  """
  def calculate_brightness_from_elevation(elevation_angle, params \\ %{}) do
    params = merge_default_params(params)

    cond do
      # Sun well below horizon - night
      elevation_angle < -18.0 ->
        params.min_brightness

      # Astronomical twilight (-18° to -12°)
      elevation_angle < -12.0 ->
        # Very gradual increase from 0 to 10% of max brightness
        progress = (elevation_angle + 18.0) / 6.0
        smooth_progress = smooth_curve(progress)
        params.min_brightness + smooth_progress * 0.1 * params.max_brightness

      # Nautical twilight (-12° to -6°)
      elevation_angle < -6.0 ->
        # Increase from 10% to 25% of max brightness
        progress = (elevation_angle + 12.0) / 6.0
        smooth_progress = smooth_curve(progress)
        0.1 * params.max_brightness + smooth_progress * 0.15 * params.max_brightness

      # Civil twilight (-6° to 0°)
      elevation_angle < 0.0 ->
        # Increase from 25% to 60% of max brightness
        progress = (elevation_angle + 6.0) / 6.0
        smooth_progress = smooth_curve(progress)
        0.25 * params.max_brightness + smooth_progress * 0.35 * params.max_brightness

      # Sun above horizon (0° to 90°)
      elevation_angle >= 0.0 ->
        # Increase from 60% to 100% based on elevation
        # Peak at solar noon (around 23.5° + latitude dependent)
        # Approximate maximum solar elevation
        max_elevation = 66.5
        normalized_elevation = min(elevation_angle / max_elevation, 1.0)

        # Use sine curve for natural brightness progression
        brightness_factor = :math.sin(normalized_elevation * :math.pi() / 2)
        0.6 * params.max_brightness + brightness_factor * 0.4 * params.max_brightness
    end
  end

  @doc """
  Get default brightness calculation parameters.
  """
  def default_params do
    %{
      dawn_duration_minutes: @default_dawn_duration_minutes,
      dusk_duration_minutes: @default_dusk_duration_minutes,
      min_brightness: @default_min_brightness,
      max_brightness: @default_max_brightness,
      dawn_brightness: @default_dawn_brightness,
      dusk_brightness: @default_dusk_brightness
    }
  end

  # Private helper functions

  defp merge_default_params(params) do
    Map.merge(default_params(), params)
  end

  defp calculate_dawn_brightness(current_time, dawn_start, dawn_end, params) do
    total_duration = DateTime.diff(dawn_end, dawn_start, :second)
    elapsed = DateTime.diff(current_time, dawn_start, :second)
    progress = elapsed / total_duration

    # Smooth transition from min to dawn brightness
    smooth_progress = smooth_curve(progress)
    params.min_brightness + smooth_progress * (params.dawn_brightness - params.min_brightness)
  end

  defp calculate_day_brightness(current_time, sunrise_time, sunset_time, solar_noon_time, params) do
    # Calculate brightness curve during the day
    # Peak at solar noon, gradually decrease toward sunrise/sunset

    total_day_duration = DateTime.diff(sunset_time, sunrise_time, :second)
    time_since_sunrise = DateTime.diff(current_time, sunrise_time, :second)
    time_to_noon = DateTime.diff(solar_noon_time, sunrise_time, :second)

    if time_since_sunrise <= time_to_noon do
      # Morning: sunrise to solar noon
      progress = time_since_sunrise / time_to_noon
      smooth_progress = smooth_curve(progress)
      params.dawn_brightness + smooth_progress * (params.max_brightness - params.dawn_brightness)
    else
      # Afternoon: solar noon to sunset
      time_from_noon = time_since_sunrise - time_to_noon
      afternoon_duration = total_day_duration - time_to_noon
      progress = time_from_noon / afternoon_duration
      smooth_progress = smooth_curve(progress)
      params.max_brightness - smooth_progress * (params.max_brightness - params.dusk_brightness)
    end
  end

  defp calculate_dusk_brightness(current_time, dusk_start, dusk_end, params) do
    total_duration = DateTime.diff(dusk_end, dusk_start, :second)
    elapsed = DateTime.diff(current_time, dusk_start, :second)
    progress = elapsed / total_duration

    # Smooth transition from dusk brightness to min
    smooth_progress = smooth_curve(progress)
    params.dusk_brightness - smooth_progress * (params.dusk_brightness - params.min_brightness)
  end

  defp smooth_curve(progress) when progress <= 0.0, do: 0.0
  defp smooth_curve(progress) when progress >= 1.0, do: 1.0

  defp smooth_curve(progress) do
    # Smooth S-curve using sine function for natural transitions
    0.5 * (1 + :math.sin((progress - 0.5) * :math.pi()))
  end
end
