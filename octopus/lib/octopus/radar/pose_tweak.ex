defmodule Octopus.Radar.PoseTweak do
  @moduledoc false
  use Agent

  alias Octopus.Radar

  @type state :: %{
          layout_start_angle_deg: number(),
          angle_offset_deg: number()
        }

  def start_link(_opts) do
    Agent.start_link(fn -> initial_state() end, name: __MODULE__)
  end

  @spec get() :: state()
  def get, do: Agent.get(__MODULE__, & &1)

  @spec layout_start_angle_deg() :: number()
  def layout_start_angle_deg, do: Agent.get(__MODULE__, & &1.layout_start_angle_deg)

  @spec angle_offset_deg() :: number()
  def angle_offset_deg, do: Agent.get(__MODULE__, & &1.angle_offset_deg)

  @spec set_layout_start_angle_deg(number()) :: :ok
  def set_layout_start_angle_deg(deg) when is_number(deg) do
    Agent.update(__MODULE__, &Map.put(&1, :layout_start_angle_deg, normalize_deg(deg)))
  end

  @spec set_angle_offset_deg(number()) :: :ok
  def set_angle_offset_deg(deg) when is_number(deg) do
    Agent.update(__MODULE__, &Map.put(&1, :angle_offset_deg, normalize_deg(deg)))
  end

  @doc false
  @spec normalize_deg(number()) :: float()
  def normalize_deg(deg) when is_number(deg) do
    rem = :math.fmod(deg * 1.0, 360.0)
    if rem < 0, do: rem + 360.0, else: rem
  end

  defp initial_state do
    %{
      layout_start_angle_deg: config_layout_start_angle_deg(),
      angle_offset_deg: 0.0
    }
  end

  defp config_layout_start_angle_deg do
    case Application.get_env(:octopus, Radar, []) |> Keyword.get(:layout) do
      nil -> 0.0
      layout -> Keyword.get(layout, :start_angle_deg, 0) * 1.0
    end
  end
end
