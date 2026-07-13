defmodule Octopus.Radar.Transform do
  @moduledoc """
  Maps sensor-local track coordinates into the installation global frame.

  Each sensor reports positions in its own device frame. `Octopus.Radar.SensorType`
  first unifies those readings into a **canonical local frame** (origin at the
  mount, looking down, `+X` along the mounting reference, `+Y` 90° CCW,
  right-handed). This module then places that canonical frame on the global map
  using the pose keys on the merged sensor config:

    * `:angle_deg` — bearing of the sensor mount from the installation center
      (0° = global +X, CCW positive). In a radial layout this is also the
      *outward* radial direction.
    * `:distance_cm` — distance from center to the sensor mount.
    * `:rotation_deg` — small per-sensor yaw correction added to `:angle_deg`,
      used when a unit is physically misaligned relative to its intended beam.
      Defaults to `0`.

  Because the canonical `+X` points along the outward radial, aligning it with
  the global `+X` requires only a rotation by `angle_deg + rotation_deg` — no
  axis flip. The result: **local +X tracks objects moving away from the
  installation center, local +Y is 90° CCW from it.**

  The transform is a 2D rigid-body map (SE(2)): rotate canonical x/y and vx/vy
  by `angle_deg + rotation_deg`, then translate by the mount offset. `z` and
  `vz` are unchanged.
  """

  alias Octopus.Radar.{Frame, SensorType, Track}

  @type pose_config :: keyword()

  @default_sensor_type :ld6001a

  @doc """
  Transform a single track from sensor-local (raw) to global coordinates.
  """
  @spec transform_track(Track.t(), pose_config()) :: Track.t()
  def transform_track(%Track{} = track, config) do
    {tx, ty, cos_r, sin_r} = pose_factors(config)
    canonical = SensorType.to_canonical(sensor_type(config), track)

    %Track{
      canonical
      | x: tx + canonical.x * cos_r - canonical.y * sin_r,
        y: ty + canonical.x * sin_r + canonical.y * cos_r,
        vx: canonical.vx * cos_r - canonical.vy * sin_r,
        vy: canonical.vx * sin_r + canonical.vy * cos_r
    }
  end

  @doc """
  Transform every track in a frame from sensor-local to global coordinates.
  """
  @spec transform_frame(Frame.t(), pose_config()) :: Frame.t()
  def transform_frame(%Frame{} = frame, config) do
    %{frame | tracks: Enum.map(frame.tracks, &transform_track(&1, config))}
  end

  @doc """
  Inverse of `transform_track/2`: map a track from the installation global
  frame back into the sensor's local (raw) frame.

  Given the forward map `g = t + R·c` (with `R` the rotation by
  `angle_deg + rotation_deg`, `c` the canonical-frame track and `t` the mount
  offset), the canonical inverse is `c = Rᵀ·(g − t)`, followed by
  `SensorType.from_canonical/2` to recover raw axes. Used by
  `Octopus.Radar.Mock.Server` to turn a shared world object into the local
  coordinates a sensor at this pose would report — so that feeding the result
  back through `transform_track/2` reproduces the original global position.
  """
  @spec global_to_local_track(Track.t(), pose_config()) :: Track.t()
  def global_to_local_track(%Track{} = track, config) do
    {tx, ty, cos_r, sin_r} = pose_factors(config)

    dx = track.x - tx
    dy = track.y - ty

    canonical = %Track{
      track
      | x: dx * cos_r + dy * sin_r,
        y: -dx * sin_r + dy * cos_r,
        vx: track.vx * cos_r + track.vy * sin_r,
        vy: -track.vx * sin_r + track.vy * cos_r
    }

    SensorType.from_canonical(sensor_type(config), canonical)
  end

  @doc false
  @spec pose_factors(pose_config()) :: {float(), float(), float(), float()}
  def pose_factors(config) do
    angle_deg = Keyword.fetch!(config, :angle_deg)
    distance_cm = Keyword.fetch!(config, :distance_cm)
    rotation_deg = Keyword.get(config, :rotation_deg, 0)

    angle_rad = deg_to_rad(angle_deg)
    rotation_rad = deg_to_rad(angle_deg + rotation_deg)

    distance_m = distance_cm / 100.0
    tx = distance_m * :math.cos(angle_rad)
    ty = distance_m * :math.sin(angle_rad)
    cos_r = :math.cos(rotation_rad)
    sin_r = :math.sin(rotation_rad)

    {tx, ty, cos_r, sin_r}
  end

  defp sensor_type(config), do: Keyword.get(config, :type, @default_sensor_type)

  defp deg_to_rad(deg) when is_number(deg), do: deg * :math.pi() / 180.0
end
