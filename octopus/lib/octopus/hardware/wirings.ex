defmodule Octopus.Hardware.Wirings do
  @moduledoc """
  Catalog of named panel wiring setups.
  """

  alias Octopus.Hardware.Wiring

  @wirings [
    {:serpentine_horizontal_bottom_left, nil, :serpentine_horizontal_bottom_left},
    {:serpentine_vertical_bottom_left, nil, :serpentine_vertical_bottom_left}
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
