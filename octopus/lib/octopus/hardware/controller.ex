defmodule Octopus.Hardware.Controller do
  @moduledoc """
  A physical Blinkenled controller in the hardware catalog.

  `max_pixel_count` is the maximum number of addressable pixels on the device.
  Installations may use fewer pixels via `panel_layout`, but never more.

  Multi-port devices set `ports` > 1. Installation slots select a 1-based
  `port`; the UDP listen port is `udp_port_base + (port - 1)`.
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
    :firmware_version,
    ports: 1,
    udp_port_base: 1337
  ]

  @type t :: %__MODULE__{
          id: atom(),
          firmware_panel_index: pos_integer(),
          hostname: String.t(),
          mac: String.t() | nil,
          max_pixel_count: pos_integer(),
          firmware_matrix: {pos_integer(), pos_integer()},
          firmware_wire_map: :serpentine_horizontal_bottom_left,
          firmware_version: String.t() | nil,
          ports: pos_integer(),
          udp_port_base: pos_integer()
        }

  @doc "UDP listen port for 1-based installation slot port `port`."
  @spec udp_port(t(), pos_integer()) :: pos_integer()
  def udp_port(%__MODULE__{udp_port_base: base}, port) when is_integer(port) and port >= 1 do
    base + (port - 1)
  end
end
