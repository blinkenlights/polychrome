defmodule Octopus.Radar.Track do
  @moduledoc """
  A single tracked target inside a radar frame.

  Field semantics follow the HLK-LD6001A-60G manual §10 and §16.2:

    * `id` – target identifier (`uint32`), assigned by the device's internal
      tracker and called the "personnel identification number" in the manual.
      Stable across consecutive frames while the device maintains the track.
      **May be reused** after a track disappears (manual §18, §22) — that is,
      the same `id` later in time does not necessarily refer to the same
      physical target.
    * `reserved` – the unused leading `uint32` field of the on-wire personnel
      record. Kept here only so consumers that want full fidelity can see it.
    * `x`, `y`, `z` – position in **meters**.
    * `vx`, `vy`, `vz` – velocity in **meters / second**.

  The coordinate system is defined by the manual:

    * `x` – left/right
    * `y` – front/back
    * `z` – height (the device is ceiling-mounted, looking down).
  """

  defstruct [:id, :reserved, :x, :y, :z, :vx, :vy, :vz]

  @type t :: %__MODULE__{
          id: non_neg_integer(),
          reserved: non_neg_integer(),
          x: float(),
          y: float(),
          z: float(),
          vx: float(),
          vy: float(),
          vz: float()
        }
end
