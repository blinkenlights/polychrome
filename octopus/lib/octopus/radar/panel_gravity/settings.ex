defmodule Octopus.Radar.PanelGravity.Settings do
  @moduledoc false
  use Agent

  @defaults %{
    exponent: 3.0,
    softening_m: 0.25,
    # Dimensionless 1..100: low = steep falloff, high = far panels still get weight.
    reach: 50,
    mass: 1.0,
    min_ref: 1.0e-4,
    ref_tau: 4.0,
    sensitivity: 1.0,
    contrast: 3.0,
    adaptive: true,
    # Quick but visible rise, ~3s fade so a brief dropout or occlusion doesn't
    # snap to black — see `Core.smooth_asymmetric/4`.
    attack_tau: 0.2,
    release_tau: 3.0,
    # Cross-sensor fusion (Octopus.Radar.TrackFusion) now covers duplicate
    # detections, so this only needs to bridge genuinely missed frames —
    # release_tau handles the visual smoothing of real disappearances.
    track_stale_ms: 400,
    tick_hz: 25,
    broadcast_epsilon: 0.001
  }

  defstruct [
    :exponent,
    :softening_m,
    :reach,
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
    :broadcast_epsilon
  ]

  @type t :: %__MODULE__{
          exponent: float(),
          softening_m: float(),
          reach: number(),
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
      struct(state, normalize_opts(opts))
    end)
  end

  @spec defaults() :: map()
  def defaults, do: @defaults

  defp initial_state do
    with radar when not is_nil(radar) <- Octopus.Installation.radar_config(),
         panel_gravity <- Keyword.get(radar, :panel_gravity, []),
         merged <-
           @defaults
           |> Map.to_list()
           |> Keyword.merge(normalize_opts(panel_gravity)) do
      struct(__MODULE__, merged)
    else
      _ -> struct(__MODULE__, @defaults)
    end
  end

  # Drop legacy :reach_m and clamp :reach into 1..100.
  defp normalize_opts(opts) when is_list(opts) do
    opts
    |> Keyword.delete(:reach_m)
    |> Enum.map(fn
      {:reach, value} -> {:reach, clamp_reach(value)}
      other -> other
    end)
  end

  defp clamp_reach(value) when is_number(value) do
    value |> max(1) |> min(100)
  end

  defp clamp_reach(_), do: @defaults.reach
end
