defmodule Octopus.Hardware.Wiring do
  @moduledoc """
  Named description of how LEDs are physically daisy-chained on a panel type.
  """

  @enforce_keys [:id, :matrix, :type]
  defstruct [:id, :matrix, :type]

  @type type ::
          :serpentine_8x8_bottom_left
          | :serpentine_8x8_vertical_bottom_left
          | :linear_strip

  @type t :: %__MODULE__{
          id: atom(),
          matrix: {pos_integer(), pos_integer()},
          type: type()
        }
end
