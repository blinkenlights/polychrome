defmodule Octopus.Radar.SensorType do
  @moduledoc """
  Per-sensor-type local coordinate conventions.

  Every sensor is unified into one **canonical local frame** before the global
  `Octopus.Radar.Transform` places it on the map. The canonical frame is:

    * origin at the sensor, which hovers at `height_cm` looking straight down at
      the ground;
    * **+X** = the sensor's mounting-reference axis. In a `:radial` layout this
      axis is aligned *outward* — pointing away from the installation center —
      via the pose `:angle_deg`;
    * **+Y** = 90° counter-clockwise from +X (right-handed frame, +Z pointing up
      out of the ground);
    * `z` = height above the ground.

  A concrete sensor type only has to declare, via `to_canonical/2`, how its
  *raw* reported axes map into this frame (and the inverse via
  `from_canonical/2`, used to synthesise readings in mock mode). New sensor
  types with different native conventions add clauses here and nothing else in
  the pipeline changes.

  ## HLK-LD6001A

  Mounted on the ceiling facing down, the LD6001A reports a right-handed frame
  (vendor manual §10: `X` lateral, `Y` front/back, `Z` height). Read as a
  top-down plot it behaves "flipped" — objects to the left get `+x`, objects
  toward the bottom get `+y`. That is the standard math frame rotated 180°, not
  a mirror image, so it is still right-handed. Because we mount the unit so its
  raw `+x` points outward, the raw axes already coincide with the canonical
  frame above: **the mapping is the identity**.
  """

  alias Octopus.Radar.Track

  @supported [:ld6001a]

  @doc "Sensor types with a defined coordinate convention."
  @spec supported() :: [atom()]
  def supported, do: @supported

  @doc """
  Rewrite a raw track from a sensor type's native axes into the canonical local
  frame described in the moduledoc.
  """
  @spec to_canonical(atom(), Track.t()) :: Track.t()
  def to_canonical(:ld6001a, %Track{} = track), do: track

  @doc """
  Inverse of `to_canonical/2`: express a canonical-frame track in a sensor
  type's native raw axes. Used by the mock device to fabricate readings.
  """
  @spec from_canonical(atom(), Track.t()) :: Track.t()
  def from_canonical(:ld6001a, %Track{} = track), do: track
end
