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

  ### Sensitivity (`AT+DPKTH`)

  Installations use presets (`:normal`, `:lower`, `:higher`) or an explicit
  device-native integer. On this module, **higher DPKTH means lower real
  sensitivity**. Presets default to vendor `:normal` = DPKTH 4. The UI slider
  uses an inverted 1..9 level where 1 = least sensitive and 9 = most.
  """

  alias Octopus.Radar.Track

  @supported [:ld6001a]

  @type sensitivity_preset :: :normal | :lower | :higher
  @type sensitivity_setting :: sensitivity_preset() | pos_integer()

  @ld6001a_dpkth_range 1..9
  @ld6001a_presets %{
    normal: 4,
    lower: 6,
    higher: 2
  }

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

  @doc """
  Default sensitivity preset for installations (maps to the vendor default on
  each sensor type).
  """
  @spec default_sensitivity_setting() :: sensitivity_preset()
  def default_sensitivity_setting, do: :normal

  @doc """
  Resolve an installation or deployment sensitivity setting to the device-native
  value used in AT init (e.g. `AT+DPKTH` on the LD6001A).

  Accepts presets (`:normal`, `:lower`, `:higher`) or an explicit device-native
  integer for advanced tuning.
  """
  @spec resolve_sensitivity(atom(), sensitivity_setting()) :: pos_integer()
  def resolve_sensitivity(type, setting)

  def resolve_sensitivity(:ld6001a, preset) when preset in [:normal, :lower, :higher] do
    Map.fetch!(@ld6001a_presets, preset)
  end

  def resolve_sensitivity(:ld6001a, value) when is_integer(value) and value in @ld6001a_dpkth_range do
    value
  end

  def resolve_sensitivity(type, setting) do
    raise ArgumentError,
          "radar sensor type #{inspect(type)}: invalid sensitivity #{inspect(setting)}"
  end

  @doc """
  UI sensitivity level on a 1..9 scale where **1 = least sensitive** and
  **9 = most sensitive** (independent of device register semantics).
  """
  @spec sensitivity_level(atom(), pos_integer()) :: 1..9
  def sensitivity_level(type, device_value)

  def sensitivity_level(:ld6001a, value) when value in @ld6001a_dpkth_range do
    10 - value
  end

  @doc "Convert a UI sensitivity level to the device-native value."
  @spec level_to_device_value(atom(), 1..9) :: pos_integer()
  def level_to_device_value(type, level)

  def level_to_device_value(:ld6001a, level) when level in 1..9 do
    10 - level
  end

  @doc "Human label for a UI sensitivity level (1 = least, 9 = most)."
  @spec sensitivity_level_label(1..9) :: String.t()
  def sensitivity_level_label(level) when level in 1..9 do
    cond do
      level <= 2 -> "low"
      level <= 4 -> "moderate-low"
      level <= 6 -> "moderate"
      level <= 8 -> "moderate-high"
      true -> "high"
    end
  end
end
