defmodule Octopus.Hardware.Controller do
  @moduledoc """
  A physical Blinkenled controller in the hardware catalog.
  """

  @enforce_keys [
    :id,
    :firmware_panel_index,
    :hostname,
    :pixel_count,
    :firmware_matrix,
    :firmware_wire_map
  ]
  defstruct [
    :id,
    :firmware_panel_index,
    :hostname,
    :mac,
    :pixel_count,
    :firmware_matrix,
    :firmware_wire_map,
    :firmware_version
  ]

  @type t :: %__MODULE__{
          id: atom(),
          firmware_panel_index: pos_integer(),
          hostname: String.t(),
          mac: String.t() | nil,
          pixel_count: pos_integer(),
          firmware_matrix: {pos_integer(), pos_integer()},
          firmware_wire_map: :serpentine_8x8_bottom_left,
          firmware_version: String.t() | nil
        }
end
