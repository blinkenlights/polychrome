defmodule Octopus.Hardware.PanelLayout do
  @moduledoc """
  Maps panel layout coordinates to linear pixel indices.

  Phase 2 supports per-panel layout shapes beyond the default 8×8 matrix.
  """

  @doc """
  Maps `(x, y)` in top-left layout coordinates to a linear pixel index.
  """
  @spec to_index({non_neg_integer(), non_neg_integer()}, {pos_integer(), pos_integer()}) ::
          non_neg_integer()
  def to_index({x, y}, {width, _height}) do
    x + y * width
  end

  @doc """
  Maps a linear pixel index back to `{x, y}` layout coordinates.
  """
  @spec from_index(non_neg_integer(), {pos_integer(), pos_integer()}) ::
          {non_neg_integer(), non_neg_integer()}
  def from_index(index, {width, _height}) do
    {rem(index, width), div(index, width)}
  end
end
