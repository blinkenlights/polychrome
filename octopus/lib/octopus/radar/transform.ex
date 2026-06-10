defmodule Octopus.Radar.Transform do
  @moduledoc """
  Maps sensor-local track coordinates into the installation global frame.

  Each sensor reports positions in its own frame (origin at the mount point,
  axes aligned with the device). Pose keys on the merged sensor config define
  how to express those readings in a shared frame whose origin is the
  installation center:

    * `:angle_deg` — bearing of the sensor mount from center (0° = +X, CCW)
    * `:distance_cm` — distance from center to sensor mount
    * `:rotation_deg` — sensor yaw relative to global axes (CCW)

  The transform is a 2D rigid body map (SE(2)): rotate local x/y and vx/vy,
  then translate by the mount offset. `z` and `vz` are unchanged.
  """

  alias Octopus.Radar.{Frame, Track}

  @type pose_config :: keyword()

  @doc """
  Transform a single track from sensor-local to global coordinates.
  """
  @spec transform_track(Track.t(), pose_config()) :: Track.t()
  def transform_track(%Track{} = track, config) do
    {tx, ty, cos_r, sin_r} = pose_factors(config)

    %Track{
      track
      | x: tx + track.x * cos_r - track.y * sin_r,
        y: ty + track.x * sin_r + track.y * cos_r,
        vx: track.vx * cos_r - track.vy * sin_r,
        vy: track.vx * sin_r + track.vy * cos_r
    }
  end

  @doc """
  Transform every track in a frame from sensor-local to global coordinates.
  """
  @spec transform_frame(Frame.t(), pose_config()) :: Frame.t()
  def transform_frame(%Frame{} = frame, config) do
    %{frame | tracks: Enum.map(frame.tracks, &transform_track(&1, config))}
  end

  @doc false
  @spec pose_factors(pose_config()) :: {float(), float(), float(), float()}
  def pose_factors(config) do
    angle_deg = Keyword.fetch!(config, :angle_deg)
    distance_cm = Keyword.fetch!(config, :distance_cm)
    rotation_deg = Keyword.fetch!(config, :rotation_deg)

    angle_rad = deg_to_rad(angle_deg)
    rotation_rad = deg_to_rad(rotation_deg)

    distance_m = distance_cm / 100.0
    tx = distance_m * :math.cos(angle_rad)
    ty = distance_m * :math.sin(angle_rad)
    cos_r = :math.cos(rotation_rad)
    sin_r = :math.sin(rotation_rad)

    {tx, ty, cos_r, sin_r}
  end

  defp deg_to_rad(deg) when is_number(deg), do: deg * :math.pi() / 180.0
end
