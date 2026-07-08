defmodule Octopus.Hardware.Controller do
  @moduledoc """
  A physical Blinkenled controller in the hardware catalog.

  `max_pixel_count` is the maximum number of addressable pixels on the device.
  Installations may use fewer pixels via `panel_layout`, but never more.
  """

  @enforce_keys [
    :id,
    :firmware_panel_index,
    :hostname,
    :max_pixel_count,
    :firmware_matrix,
    :firmware_wire_map
  ]
  defstruct [
    :id,
    :firmware_panel_index,
    :hostname,
    :mac,
    :max_pixel_count,
    :firmware_matrix,
    :firmware_wire_map,
    :firmware_version
  ]

  @type t :: %__MODULE__{
          id: atom(),
          firmware_panel_index: pos_integer(),
          hostname: String.t(),
          mac: String.t() | nil,
          max_pixel_count: pos_integer(),
          firmware_matrix: {pos_integer(), pos_integer()},
          firmware_wire_map: :serpentine_horizontal_bottom_left,
          firmware_version: String.t() | nil
        }
end
