defmodule Octopus.Radar.PanelGravity.Settings do
  @moduledoc false
  use Agent

  # Distance at which a panel reaches 100 % gravity (object is this close).
  @default_near_dist_m 1.0

  @defaults %{
    # Symmetric first-order lag applied to every panel level on each flush.
    easing_tau: 1.5,
    # Cross-sensor fusion (Octopus.Radar.TrackFusion) now covers duplicate
    # detections, so this only needs to bridge genuinely missed frames.
    track_stale_ms: 400,
    broadcast_epsilon: 0.001,
    # When true (default), cross-sensor duplicates are collapsed via fuse_people/1
    # before gravity computation. Switch to false to use raw per-sensor tracks
    # (post clutter-filter) directly — useful when fusion produces wrong combined
    # positions due to sensor calibration issues.
    fuse_people: true,
    # Distance thresholds for the linear gravity ramp.
    # near_dist_m: object at this distance → max_gravity_pct
    # far_dist_m:  object at this distance → floor_pct  (typically ring_radius - platform_radius)
    near_dist_m: @default_near_dist_m,
    far_dist_m: 7.75,
    # Brightness range (percent 0..100).
    # floor_pct:       base brightness for all panels, even with no objects in range.
    # max_gravity_pct: brightness when an object is at near_dist_m.
    floor_pct: 5,
    max_gravity_pct: 100
  }

  defstruct [
    :easing_tau,
    :track_stale_ms,
    :broadcast_epsilon,
    :fuse_people,
    :near_dist_m,
    :far_dist_m,
    :floor_pct,
    :max_gravity_pct
  ]

  @type t :: %__MODULE__{
          easing_tau: float(),
          track_stale_ms: pos_integer(),
          broadcast_epsilon: float(),
          fuse_people: boolean(),
          near_dist_m: float(),
          far_dist_m: float(),
          floor_pct: number(),
          max_gravity_pct: number()
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
    # Derive the far-distance default from the installation geometry so the
    # radar UI starts with a sensible value without any manual configuration.
    far_dist_default = compute_far_dist_default()

    struct(__MODULE__, Map.put(@defaults, :far_dist_m, far_dist_default))
  end

  # ring_radius - platform_radius gives the usable detection corridor.
  defp compute_far_dist_default do
    ring_r = Octopus.Installation.ring_radius_m()
    plat_r = Octopus.Installation.platform_radius_m() || 0.0
    max(ring_r - plat_r, @default_near_dist_m + 0.1)
  rescue
    _ -> @defaults.far_dist_m
  end

  # Silently drop any keys that belonged to the old exponential gravity model
  # so existing installation configs don't break on update.
  @legacy_keys [:exponent, :softening_m, :reach, :reach_m, :mass, :min_ref, :ref_tau,
                :sensitivity, :contrast, :adaptive, :velocity_gain, :tick_hz]

  defp normalize_opts(opts) when is_list(opts) do
    opts
    |> Enum.reject(fn {k, _} -> k in @legacy_keys end)
    |> Enum.map(fn
      {:near_dist_m, v}    -> {:near_dist_m, clamp_num(v, 0.1, 10.0)}
      {:far_dist_m, v}     -> {:far_dist_m, clamp_num(v, 0.2, 30.0)}
      {:floor_pct, v}      -> {:floor_pct, clamp_num(v, 0, 100)}
      {:max_gravity_pct, v}-> {:max_gravity_pct, clamp_num(v, 0, 100)}
      other -> other
    end)
  end

  defp clamp_num(v, lo, hi) when is_number(v), do: v |> max(lo) |> min(hi)
  defp clamp_num(_, lo, _), do: lo
end
