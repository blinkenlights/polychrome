defmodule Octopus.Radar.Sensitivity do
  @moduledoc false
  use Agent

  alias Octopus.Radar.SensorType

  def start_link(_opts) do
    Agent.start_link(fn -> initial_level() end, name: __MODULE__)
  end

  @spec level() :: 1..9
  def level, do: Agent.get(__MODULE__, & &1)

  @spec set_level(1..9) :: :ok
  def set_level(level) when is_integer(level) and level in 1..9 do
    Agent.update(__MODULE__, fn _ -> level end)
  end

  defp initial_level do
    with radar when not is_nil(radar) <- Octopus.Installation.radar_config(),
         defaults <- Keyword.get(radar, :defaults, []),
         setting <- Keyword.get(defaults, :sensitivity, SensorType.default_sensitivity_setting()),
         device_value <- SensorType.resolve_sensitivity(:ld6001a, setting) do
      SensorType.sensitivity_level(:ld6001a, device_value)
    else
      _ -> 6
    end
  end
end
