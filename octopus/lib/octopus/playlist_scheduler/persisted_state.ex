defmodule Octopus.PlaylistScheduler.PersistedState do
  @moduledoc """
  Ecto schema for the singleton row that persists the PlaylistScheduler runtime state
  (which playlist was active, at which index, and whether it was running) across restarts.
  Always at most one row in the table; `load/0` and `save/1` handle the insert-or-update logic.
  """

  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query, only: [from: 2]

  alias Octopus.Repo

  schema "playlist_scheduler_state" do
    field :playlist_id, :string
    field :index, :integer, default: 0
    field :running, :boolean, default: false

    timestamps()
  end

  @fields [:playlist_id, :index, :running]

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
