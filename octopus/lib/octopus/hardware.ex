defmodule Octopus.Hardware do
  @moduledoc """
  Hardware catalog and panel untangling support.
  """

  alias Octopus.Hardware.{Controller, Controllers, Wiring, Wirings}

  @doc """
  Returns the full controller registry.
  """
  @spec registry() :: %{atom() => Controller.t()}
  def registry, do: Controllers.all()

  @doc """
  Returns the full wiring registry.
  """
  @spec wiring_registry() :: %{atom() => Wiring.t()}
  def wiring_registry, do: Wirings.all()

  @doc """
  Looks up a controller by id. Raises if unknown.
  """
  @spec fetch!(atom()) :: Controller.t()
  def fetch!(id) do
    case Map.fetch(registry(), id) do
      {:ok, controller} -> controller
      :error -> raise ArgumentError, "unknown controller id #{inspect(id)}"
    end
  end

  @doc """
  Looks up a controller by id.
  """
  @spec fetch(atom()) :: {:ok, Controller.t()} | :error
  def fetch(id), do: Map.fetch(registry(), id)

  @doc """
  Looks up a wiring setup by id. Raises if unknown.
  """
  @spec fetch_wiring!(atom()) :: Wiring.t()
  def fetch_wiring!(id) do
    case Map.fetch(wiring_registry(), id) do
      {:ok, wiring} -> wiring
      :error -> raise ArgumentError, "unknown wiring id #{inspect(id)}"
    end
  end

  @doc """
  Looks up a wiring setup by id.
  """
  @spec fetch_wiring(atom()) :: {:ok, Wiring.t()} | :error
  def fetch_wiring(id), do: Map.fetch(wiring_registry(), id)
end
