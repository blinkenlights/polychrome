defmodule Octopus.Apps.Hogg.Util do
  def clamp(v, min, _max) when v < min, do: min
  def clamp(v, _min, max) when v > max, do: max
  def clamp(v, _, _), do: v

  def clamp(v, max) when v > max, do: max
  def clamp(v, max) when v < -max, do: -max
  def clamp(v, _), do: v
end
