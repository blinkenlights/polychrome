defmodule Octopus.Hardware.PanelSlot do
  @moduledoc """
  One logical panel slot in an installation: a controller, optional device port,
  and a wiring setup.

  `port` is the 1-based bus on a multi-port controller (default 1). UDP listen
  port is `Controller.udp_port(controller, port)`.
  """

  @enforce_keys [:controller_id, :wiring_id]
  defstruct [:controller_id, :wiring_id, port: 1]

  @type t :: %__MODULE__{
          controller_id: atom(),
          wiring_id: atom(),
          port: pos_integer()
        }
end
