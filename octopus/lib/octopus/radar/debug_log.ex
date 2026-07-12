defmodule Octopus.Radar.DebugLog do
  @moduledoc false

  require Logger

  alias Octopus.Radar.LogFormat

  @session_id "2c825b"
  @log_path "/Users/tim/src/timpritlove/polychrome/.cursor/debug-2c825b.log"

  @doc false
  @spec write(String.t(), String.t(), String.t(), map()) :: :ok
  def write(hypothesis_id, location, message, data) when is_map(data) do
    payload = %{
      sessionId: @session_id,
      hypothesisId: hypothesis_id,
      location: location,
      message: message,
      data: data,
      timestamp: System.system_time(:millisecond)
    }

    json = Jason.encode!(payload)
    Logger.info("[RADAR-DBG] #{json}")

    try do
      File.write!(@log_path, json <> "\n", [:append])
    catch
      _, _ -> :ok
    end

    :ok
  end

  @doc false
  @spec sensor_data(pos_integer(), String.t() | nil, keyword()) :: map()
  def sensor_data(device_id, port \\ nil, extra \\ []) do
    base = %{device_id: device_id, letter: LogFormat.device_letter(device_id)}

    base =
      if port do
        Map.merge(base, %{port: port, short_port: LogFormat.short_port(port)})
      else
        base
      end

    Map.merge(base, Map.new(extra))
  end
end
