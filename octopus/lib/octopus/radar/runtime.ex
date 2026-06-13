defmodule Octopus.Radar.Runtime do
  @moduledoc false
  use Agent

  @doc false
  def start_link(initial_enabled) when is_map(initial_enabled) do
    Agent.start_link(fn -> initial_enabled end, name: __MODULE__)
  end

  @doc false
  @spec enabled?(pos_integer()) :: boolean()
  def enabled?(device_id) do
    Agent.get(__MODULE__, &Map.get(&1, device_id, false))
  end

  @doc false
  @spec all() :: %{pos_integer() => boolean()}
  def all do
    Agent.get(__MODULE__, & &1)
  end

  @doc false
  @spec set(pos_integer(), boolean()) :: :ok
  def set(device_id, enabled) when is_boolean(enabled) do
    Agent.update(__MODULE__, &Map.put(&1, device_id, enabled))
  end
end
