defmodule Octopus.Radar.PanelGravity.Settings do
  @moduledoc false
  use Agent

  @defaults %{
    exponent: 3.0,
    softening_m: 0.25,
    mass: 1.0,
    min_ref: 1.0e-4,
    ref_tau: 4.0,
    sensitivity: 1.0,
    contrast: 3.0,
    adaptive: true,
    attack_tau: 0.2,
    release_tau: 2.0,
    track_stale_ms: 1500,
    tick_hz: 25,
    merge_radius_m: 0.75,
    broadcast_epsilon: 0.001
  }

  defstruct [
    :exponent,
    :softening_m,
    :mass,
    :min_ref,
    :ref_tau,
    :sensitivity,
    :contrast,
    :adaptive,
    :attack_tau,
    :release_tau,
    :track_stale_ms,
    :tick_hz,
    :merge_radius_m,
    :broadcast_epsilon
  ]

  @type t :: %__MODULE__{
          exponent: float(),
          softening_m: float(),
          mass: float(),
          min_ref: float(),
          ref_tau: float(),
          sensitivity: float(),
          contrast: float(),
          adaptive: boolean(),
          attack_tau: float(),
          release_tau: float(),
          track_stale_ms: pos_integer(),
          tick_hz: pos_integer(),
          merge_radius_m: float(),
          broadcast_epsilon: float()
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
         panel_gravity <- Keyword.get(radar, :panel_gravity, []),
         merged <- Keyword.merge(Map.to_list(@defaults), panel_gravity) do
      struct(__MODULE__, merged)
    else
      _ -> struct(__MODULE__, @defaults)
    end
  end
end
