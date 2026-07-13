defmodule Octopus.Radar.SourceMode do
  @moduledoc false
  use Agent

  @type t :: :off | :live | :exact | :fuzzy

  def start_link(initial) when initial in [:off, :live, :exact, :fuzzy] do
    Agent.start_link(fn -> initial end, name: __MODULE__)
  end

  @spec get() :: t()
  def get, do: Agent.get(__MODULE__, & &1)

  @spec set(t()) :: :ok
  def set(mode) when mode in [:off, :live, :exact, :fuzzy] do
    Agent.update(__MODULE__, fn _ -> mode end)
  end
end
