defmodule Octopus.Hardware.PanelSlot do
  @moduledoc """
  One logical panel slot in an installation: a controller plus a wiring setup.
  """

  @enforce_keys [:controller_id, :wiring_id]
  defstruct [:controller_id, :wiring_id]

  @type t :: %__MODULE__{
          controller_id: atom(),
          wiring_id: atom()
        }
end
