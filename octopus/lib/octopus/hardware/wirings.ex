defmodule Octopus.Hardware.Wirings do
  @moduledoc """
  Catalog of named panel wiring setups.
  """

  alias Octopus.Hardware.Wiring

  @wirings [
    {:serpentine_8x8_bottom_left, {8, 8}, :serpentine_8x8_bottom_left},
    {:serpentine_8x8_vertical_bottom_left, {8, 8}, :serpentine_8x8_vertical_bottom_left},
    {:linear_strip, {64, 1}, :linear_strip}
  ]

  @doc """
  Returns all wiring setups as a map of wiring id => `%Wiring{}`.
  """
  @spec all() :: %{atom() => Wiring.t()}
  def all do
    Map.new(@wirings, fn {id, matrix, type} ->
      {id, %Wiring{id: id, matrix: matrix, type: type}}
    end)
  end

  @doc """
  Returns all wiring ids in catalog definition order.
  """
  @spec ids() :: [atom()]
  def ids, do: for({id, _, _} <- @wirings, do: id)
end
