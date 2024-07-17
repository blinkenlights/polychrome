defmodule Octopus do
  @moduledoc """
  Octopus keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """

  @spec installation() :: Octopus.Installation.t()
  def installation(), do: Application.get_env(:octopus, :installation)
end
