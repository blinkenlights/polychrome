defmodule Octopus.Sunlight.LocationService do
  @moduledoc """
  Service for resolving location coordinates from various sources.

  This module handles:
  - Static coordinates from installation configuration
  - Location name resolution via Nominatim API
  - Automatic IP-based geolocation as fallback

  Adapted from Fliplove.Weather location resolution patterns.
  """

  require Logger

  @ip_geolocation_url "http://ip-api.com/json"

  @doc """
  Resolves location coordinates based on installation configuration.

  Returns `{:ok, {latitude, longitude}, source}` on success.
  Returns `{:error, reason}` on failure.

  ## Examples

      iex> resolve_location({52.520008, 13.404954})
      {:ok, {52.520008, 13.404954}, "installation config"}

      iex> resolve_location("Berlin, Germany")
      {:ok, {52.520008, 13.404954}, "Nominatim lookup"}

      iex> resolve_location(:auto)
      {:ok, {52.520008, 13.404954}, "IP geolocation"}
  """
  def resolve_location(location_config) do
    case location_config do
      {lat, lon} when is_float(lat) and is_float(lon) ->
        Logger.info("Using installation coordinates: #{lat}, #{lon}")
        {:ok, {lat, lon}, "installation config"}

      location_name when is_binary(location_name) ->
        Logger.info("Resolving location name: #{location_name}")
        resolve_via_nominatim(location_name)

      :auto ->
        Logger.info("Using automatic location detection via IP")
        resolve_via_ip_geolocation()

      other ->
        Logger.error("Invalid location configuration: #{inspect(other)}")
        {:error, :invalid_location_config}
    end
  end

  @doc """
  Resolves location coordinates using the Nominatim service.
  """
  def resolve_via_nominatim(location_name) when is_binary(location_name) do
    query_params = %{
      q: location_name,
      format: "json",
      limit: "1"
    }

    url = "https://nominatim.openstreetmap.org/search?" <> URI.encode_query(query_params)
    headers = [{"User-Agent", "Octopus/1.0"}]

    # Configure request with retries and timeout
    request_options = [
      retry: :transient,
      max_retries: 3,
      retry_delay: fn attempt -> trunc(:math.pow(2, attempt - 1) * 500) end,
      connect_options: [timeout: 10_000],
      receive_timeout: 10_000
    ]

    case Req.get(url, Keyword.merge([headers: headers], request_options)) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        case body do
          [%{"lat" => lat_str, "lon" => lon_str} | _] ->
            {lat, _} = Float.parse(lat_str)
            {lon, _} = Float.parse(lon_str)
            Logger.info("Resolved '#{location_name}' to coordinates: #{lat}, #{lon}")
            {:ok, {lat, lon}, "Nominatim lookup"}

          [] ->
            Logger.warning("Location '#{location_name}' not found via Nominatim")
            {:error, :location_not_found}

          _ ->
            Logger.error("Unexpected Nominatim response format: #{inspect(body)}")
            {:error, :invalid_response}
        end

      {:ok, %Req.Response{status: status}} ->
        Logger.error("Nominatim API returned HTTP #{status}")
        {:error, :api_error}

      {:error, reason} ->
        Logger.error("Nominatim API request failed: #{inspect(reason)}")
        {:error, :network_error}
    end
  end

  @doc """
  Resolves location coordinates using IP geolocation.
  """
  def resolve_via_ip_geolocation do
    # Configure request with retries and timeout
    request_options = [
      retry: :transient,
      max_retries: 3,
      retry_delay: fn attempt -> trunc(:math.pow(2, attempt - 1) * 500) end,
      connect_options: [timeout: 10_000],
      receive_timeout: 10_000
    ]

    case Req.get(@ip_geolocation_url, request_options) do
      {:ok, %Req.Response{status: 200, body: %{"lat" => lat, "lon" => lon}}} ->
        Logger.info("Resolved location via IP geolocation: #{lat}, #{lon}")
        {:ok, {lat, lon}, "IP geolocation"}

      {:ok, %Req.Response{status: 200, body: body}} ->
        Logger.error("Unexpected IP geolocation response format: #{inspect(body)}")
        {:error, :invalid_response}

      {:ok, %Req.Response{status: status}} ->
        Logger.error("IP geolocation service returned HTTP #{status}")
        {:error, :api_error}

      {:error, reason} ->
        Logger.error("IP geolocation request failed: #{inspect(reason)}")
        {:error, :network_error}
    end
  end
end
