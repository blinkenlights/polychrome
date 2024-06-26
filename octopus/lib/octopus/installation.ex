defmodule Octopus.Installation do
  @typedoc """
  Position of a pixel, used to map content onto the installation.
  """
  @type pixel :: {integer(), integer()}

  @doc """
  Returns the positions of the pixels in the installation
  """
  @callback pixels() :: list(pixel())

  @callback simulator_layouts() :: nonempty_list(Octopus.Layout.t())
end
