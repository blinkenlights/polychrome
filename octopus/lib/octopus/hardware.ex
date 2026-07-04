defmodule Octopus.Hardware do
  @moduledoc """
  Hardware catalog and panel untangling support.
  """

  alias Octopus.Hardware.{Panel, Panels}

  @doc """
  Returns the full panel registry.
  """
  @spec registry() :: %{atom() => Panel.t()}
  def registry, do: Panels.all()

  @doc """
  Looks up a panel by id. Raises if unknown.
  """
  @spec fetch!(atom()) :: Panel.t()
  def fetch!(id) do
    case Map.fetch(registry(), id) do
      {:ok, panel} -> panel
      :error -> raise ArgumentError, "unknown panel id #{inspect(id)}"
    end
  end

  @doc """
  Looks up a panel by id.
  """
  @spec fetch(atom()) :: {:ok, Panel.t()} | :error
  def fetch(id), do: Map.fetch(registry(), id)
end
