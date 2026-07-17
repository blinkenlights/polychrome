defmodule Octopus.InstallationTransport.PersistedState do
  @moduledoc """
  Ecto schema for the singleton row that persists the InstallationTransport rotation queue
  across restarts. Always at most one row in the table; `load/0` and `save/1` handle the
  insert-or-update logic.
  """

  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query, only: [from: 2]

  alias Octopus.Repo

  schema "installation_transport_state" do
    field :queue, {:array, :map}, default: []
    field :cycle_index, :integer, default: 0
    field :cycle_interval_seconds, :float, default: 300.0
    field :transition_duration_seconds, :float, default: 1.0
    field :playing, :boolean, default: true

    timestamps()
  end

  @fields [:queue, :cycle_index, :cycle_interval_seconds, :transition_duration_seconds, :playing]

  def changeset(record, attrs \\ %{}) do
    record
    |> cast(attrs, @fields)
    |> validate_required(@fields)
  end

  @doc "Returns the persisted state row, or nil if none has been saved yet."
  def load do
    Repo.one(from(s in __MODULE__, limit: 1))
  end

  @doc "Upserts the given attribute map into the singleton row."
  def save(attrs) do
    record = load() || %__MODULE__{}

    record
    |> changeset(attrs)
    |> Repo.insert_or_update!()
  end
end
