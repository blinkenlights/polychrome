defmodule Octopus.Radar.Frame do
  @moduledoc """
  A single decoded radar frame in `AT+DEBUG=3` "detailed protocol" mode.

  See the HLK-LD6001A-60G manual §12–§17 for the on-wire structure. The frame
  itself is a snapshot of the current scene; the list in `:tracks` is the set
  of targets the device is currently tracking.

    * `frame_number` – monotonically increasing `uint32` from the device.
    * `tracks` – list of `Octopus.Radar.Track`, derived from the personnel
      records in the tracking payload. May be empty.
    * `received_at` – host monotonic timestamp (`System.monotonic_time/1`,
      `:millisecond`) recorded when the parser finished decoding the frame.

  The frame deliberately does **not** carry a `device_id`. When delivered via
  Phoenix.PubSub the device id is part of the message envelope:
  `{:radar_frame, device_id, %Octopus.Radar.Frame{}}`.
  """

  alias Octopus.Radar.Track

  defstruct [:frame_number, :tracks, :received_at]

  @type t :: %__MODULE__{
          frame_number: non_neg_integer(),
          tracks: [Track.t()],
          received_at: integer()
        }
end
