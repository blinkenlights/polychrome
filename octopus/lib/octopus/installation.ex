defmodule Octopus.Installation do
  @typedoc """
  Logical position of a pixel in the installation
  """
  @type pixel :: {integer(), integer()}

  @doc """
  Returns a list of panels with all of the pixels
  """
  @callback panels() :: nonempty_list(nonempty_list(pixel()))

  @callback width() :: integer()
  @callback height() :: integer()

  @callback center_x() :: number()
  @callback center_y() :: number()

  @callback simulator_layouts() :: nonempty_list(Octopus.Layout.t())
end
