defmodule Octopus.Radar.PanelActivity.Settings do
  @moduledoc false
  use Agent

  @defaults %{
    walk_threshold: 0.35,
    radius_weight_max: 3.0,
    min_ref: 4.0,
    ref_tau: 8.0,
    sensitivity: 1.0,
    adaptive: true,
    attack_tau: 0.2,
    release_tau: 5.0,
    track_stale_ms: 1500,
    tick_hz: 25
  }

  defstruct [
    :walk_threshold,
    :radius_weight_max,
    :min_ref,
    :ref_tau,
    :sensitivity,
    :adaptive,
    :attack_tau,
    :release_tau,
    :track_stale_ms,
    :tick_hz
  ]

  @type t :: %__MODULE__{
          walk_threshold: float(),
          radius_weight_max: float(),
          min_ref: float(),
          ref_tau: float(),
          sensitivity: float(),
          adaptive: boolean(),
          attack_tau: float(),
          release_tau: float(),
          track_stale_ms: pos_integer(),
          tick_hz: pos_integer()
        }

  def start_link(_opts) do
    Agent.start_link(fn -> initial_state() end, name: __MODULE__)
  end

  @spec get() :: t()
  def get, do: Agent.get(__MODULE__, & &1)

  @spec update(keyword()) :: :ok
  def update(opts) when is_list(opts) do
    Agent.update(__MODULE__, fn state ->
      struct(state, opts)
    end)
  end

  @spec defaults() :: map()
  def defaults, do: @defaults

  defp initial_state do
    with radar when not is_nil(radar) <- Octopus.Installation.radar_config(),
         panel_activity <- Keyword.get(radar, :panel_activity, []),
         merged <- Keyword.merge(Map.to_list(@defaults), panel_activity) do
      struct(__MODULE__, merged)
    else
      _ -> struct(__MODULE__, @defaults)
    end
  end
end
